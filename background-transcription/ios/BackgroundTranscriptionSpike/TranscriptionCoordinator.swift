import AVFAudio
import BackgroundTasks
import Foundation
import Speech

final class TranscriptionCoordinator {
    static let shared = TranscriptionCoordinator()
    private static let taskIdentifierPrefix = "ai.ansight.testapps.backgroundtranscription.processing"

    private let store = RunStore.shared
    private let stateLock = NSLock()
    private var activeRecognitionTask: SFSpeechRecognitionTask?
    private var activeBackgroundTask: BGContinuedProcessingTask?
    private var activeAudioEngine: AVAudioEngine?
    private var activeBufferRequest: SFSpeechAudioBufferRecognitionRequest?
    private var microphoneFinishWorkItem: DispatchWorkItem?
    private var microphoneFinalizationWorkItem: DispatchWorkItem?
    private var microphoneTranscriptPrefix = ""
    private var microphoneIsFinishing = false
    private var cancelledRunIds = Set<String>()
    private var registeredIdentifiers = Set<String>()

    private init() {}

    private func registerBackgroundHandler(identifier: String) -> Bool {
        stateLock.lock()
        if registeredIdentifiers.contains(identifier) {
            stateLock.unlock()
            return true
        }
        stateLock.unlock()

        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.execute(continuedTask)
        }
        if registered {
            stateLock.lock()
            registeredIdentifiers.insert(identifier)
            stateLock.unlock()
        }
        return registered
    }

    func reconcilePersistedRunOnLaunch() {
        let run = store.load()
        guard !run.phase.isTerminal, run.phase != .idle else { return }

        let identifier = taskIdentifier(for: run.id)
        guard registerBackgroundHandler(identifier: identifier) else {
            interruptPersistedRun(run, reason: "The prior task could not be restored after the app restarted.")
            return
        }

        BGTaskScheduler.shared.getPendingTaskRequests { [weak self] requests in
            guard let self else { return }
            let requestIsPending = requests.contains { $0.identifier == identifier }
            self.stateLock.lock()
            let taskIsActive = self.activeBackgroundTask?.identifier == identifier
            self.stateLock.unlock()
            guard !requestIsPending, !taskIsActive else { return }
            self.interruptPersistedRun(
                run,
                reason: "The prior task was interrupted when the app process stopped. Start a new run."
            )
        }
    }

    func requestAndSchedule(duration: RecordingDuration, source: TranscriptionSource) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.saveImmediateFailure(
                        "Speech recognition permission was not granted (status \(status.rawValue)).",
                        duration: duration,
                        source: source
                    )
                    return
                }
                guard source == .deviceMicrophone else {
                    self.schedule(duration: duration, source: source)
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self.saveImmediateFailure(
                                "Microphone permission was not granted.",
                                duration: duration,
                                source: source
                            )
                            return
                        }
                        self.schedule(duration: duration, source: source)
                    }
                }
            }
        }
    }

    func markApplicationBackgrounded() {
        let run = store.load()
        guard !run.phase.isTerminal, run.phase != .idle else { return }
        if let updated = store.update(id: run.id, { $0.backgroundedDuringRun = true }) {
            AnsightTelemetry.record("background_transcription.lifecycle.background", run: updated)
        }
    }

    func cancelCurrentRun() {
        let run = store.load()
        guard !run.phase.isTerminal, run.phase != .idle else { return }

        let identifier = taskIdentifier(for: run.id)
        stateLock.lock()
        cancelledRunIds.insert(run.id)
        let recognitionTask = activeRecognitionTask
        let backgroundTask = activeBackgroundTask
        activeRecognitionTask = nil
        activeBackgroundTask = nil
        stateLock.unlock()

        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        stopMicrophoneCapture(endAudio: true)
        recognitionTask?.cancel()
        guard let cancelledRun = store.update(id: run.id, {
            $0.phase = .cancelled
            $0.error = "Stopped by the user."
        }) else { return }
        AnsightTelemetry.record("background_transcription.cancelled", run: cancelledRun)
        completeAfterArtifactCaptureWindow(backgroundTask, success: false)
    }

    private func schedule(duration: RecordingDuration, source: TranscriptionSource) {
        guard source == .deviceMicrophone || duration.supportsInjectedFixture else {
            saveImmediateFailure(
                "The selected duration does not have a bundled archival speech fixture.",
                duration: duration,
                source: source
            )
            return
        }
        let fixtureFileName = source == .deviceMicrophone
            ? "device-microphone"
            : duration.injectedFixtureFileName ?? "none"
        let run = TranscriptionRun(
            id: UUID().uuidString,
            platform: "iOS",
            audioSource: source.rawValue,
            fixtureFileName: fixtureFileName,
            expectedDurationSeconds: duration.durationSeconds,
            startedAt: Date(),
            updatedAt: Date(),
            phase: .scheduled,
            progressPercent: 0,
            backgroundedDuringRun: false,
            transcript: "",
            error: nil
        )
        store.save(run)
        AnsightTelemetry.record("background_transcription.scheduled", run: run)
        CaptureValidationNetworkProbe.run(runId: run.id)

        let identifier = taskIdentifier(for: run.id)
        guard registerBackgroundHandler(identifier: identifier) else {
            fail(runId: run.id, message: "Background task handler registration failed; verify the permitted identifier.")
            return
        }
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: source == .deviceMicrophone ? "Transcribing microphone" : "Transcribing FDR speech",
            subtitle: source == .deviceMicrophone
                ? "\(duration.title) live microphone test"
                : "\(duration.title) archival fixture"
        )
        request.strategy = .fail

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            fail(runId: run.id, message: "Background task submission failed: \(error.localizedDescription)")
        }
    }

    private func execute(_ task: BGContinuedProcessingTask) {
        let runId = task.identifier.components(separatedBy: ".").last ?? task.identifier
        task.progress.totalUnitCount = 100
        task.progress.completedUnitCount = 1

        stateLock.lock()
        activeBackgroundTask = task
        stateLock.unlock()

        task.expirationHandler = { [weak self] in
            self?.expire(runId: runId)
        }

        update(runId: runId, phase: .preparing, progress: 1)
        let run = store.load()
        guard run.id == runId else {
            fail(runId: runId, message: "The durable run did not match the background task.")
            return
        }

        // iOS permits an active recording session to continue in the background,
        // but activating microphone capture after the app has backgrounded fails.
        // Start live capture immediately while the user-initiated app is foreground.
        if run.audioSource == TranscriptionSource.deviceMicrophone.rawValue {
            DispatchQueue.main.async {
                self.startSpeechRecognition(runId: runId, task: task)
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            for second in 1...10 {
                guard !self.isCancelled(runId) else { return }
                Thread.sleep(forTimeInterval: 1)
                let progress = second * 2
                task.progress.completedUnitCount = Int64(progress)
                task.updateTitle(
                    "Transcribing validation audio",
                    subtitle: "Background the app now — starting in \(10 - second)s"
                )
                self.update(runId: runId, phase: .preparing, progress: progress)
            }
            guard !self.isCancelled(runId) else { return }
            DispatchQueue.main.async {
                self.startSpeechRecognition(runId: runId, task: task)
            }
        }
    }

    private func startSpeechRecognition(runId: String, task: BGContinuedProcessingTask) {
        guard !isCancelled(runId) else { return }
        let run = store.load()
        guard run.id == runId else {
            fail(runId: runId, message: "The durable run did not match the background task.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            fail(runId: runId, message: "The en-US speech recognizer is unavailable on this device.")
            return
        }

        if run.audioSource == TranscriptionSource.deviceMicrophone.rawValue {
            startMicrophoneRecognition(run: run, recognizer: recognizer, task: task)
            return
        }
        guard let audioURL = Bundle.main.url(forResource: run.fixtureFileName, withExtension: "wav") else {
            fail(runId: runId, message: "Bundled \(run.fixtureFileName).wav was not found.")
            return
        }
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        beginRecognition(runId: runId, request: request, recognizer: recognizer, task: task)
    }

    private func startMicrophoneRecognition(
        run: TranscriptionRun,
        recognizer: SFSpeechRecognizer,
        task: BGContinuedProcessingTask
    ) {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .default)
            try audioSession.setActive(true)
        } catch {
            let nsError = error as NSError
            fail(
                runId: run.id,
                message: "Could not activate the microphone audio session: \(error.localizedDescription) (\(nsError.domain) \(nsError.code))."
            )
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.appendMicrophoneBuffer(buffer)
        }

        stateLock.lock()
        activeAudioEngine = engine
        activeBufferRequest = request
        microphoneTranscriptPrefix = ""
        microphoneIsFinishing = false
        stateLock.unlock()

        beginMicrophoneRecognitionSegment(
            runId: run.id,
            request: request,
            recognizer: recognizer,
            task: task
        )
        do {
            engine.prepare()
            try engine.start()
        } catch {
            fail(runId: run.id, message: "Could not start microphone capture: \(error.localizedDescription)")
            return
        }

        task.updateTitle("Transcribing live microphone", subtitle: "Speak now — microphone is recording")
        scheduleMicrophoneProgress(run: run, task: task)
    }

    private func appendMicrophoneBuffer(_ buffer: AVAudioPCMBuffer) {
        stateLock.lock()
        let request = activeBufferRequest
        stateLock.unlock()
        request?.append(buffer)
    }

    private func beginMicrophoneRecognitionSegment(
        runId: String,
        request: SFSpeechAudioBufferRecognitionRequest,
        recognizer: SFSpeechRecognizer,
        task: BGContinuedProcessingTask
    ) {
        task.progress.completedUnitCount = max(task.progress.completedUnitCount, 25)
        update(runId: runId, phase: .transcribing, progress: max(store.load().progressPercent, 25))

        let recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            self.stateLock.lock()
            let isCurrentRequest = self.activeBufferRequest === request
            let prefix = self.microphoneTranscriptPrefix
            let isFinishing = self.microphoneIsFinishing
            self.stateLock.unlock()
            guard isCurrentRequest else { return }

            if let result {
                let transcript = self.joinTranscript(prefix, result.bestTranscription.formattedString)
                let currentProgress = self.store.load().progressPercent
                let progress = isFinishing ? 90 : max(currentProgress, 65)
                task.progress.completedUnitCount = Int64(progress)
                self.update(runId: runId, phase: .transcribing, progress: progress, transcript: transcript)
                if result.isFinal {
                    if isFinishing {
                        self.complete(runId: runId, transcript: transcript)
                    } else {
                        self.restartMicrophoneRecognition(
                            runId: runId,
                            completedRequest: request,
                            transcript: transcript,
                            recognizer: recognizer,
                            task: task
                        )
                    }
                }
            } else if let error {
                if isFinishing, !self.store.load().transcript.isEmpty {
                    self.complete(runId: runId, transcript: self.store.load().transcript)
                } else {
                    self.fail(runId: runId, message: "Speech recognition failed: \(error.localizedDescription)")
                }
            }
        }
        stateLock.lock()
        if activeBufferRequest === request {
            activeRecognitionTask = recognitionTask
        } else {
            recognitionTask.cancel()
        }
        stateLock.unlock()
    }

    private func restartMicrophoneRecognition(
        runId: String,
        completedRequest: SFSpeechAudioBufferRecognitionRequest,
        transcript: String,
        recognizer: SFSpeechRecognizer,
        task: BGContinuedProcessingTask
    ) {
        DispatchQueue.main.async {
            guard !self.isCancelled(runId), !self.store.load().phase.isTerminal else { return }
            let nextRequest = SFSpeechAudioBufferRecognitionRequest()
            nextRequest.shouldReportPartialResults = true

            self.stateLock.lock()
            guard self.activeBufferRequest === completedRequest, !self.microphoneIsFinishing else {
                self.stateLock.unlock()
                return
            }
            self.microphoneTranscriptPrefix = transcript
            self.activeBufferRequest = nextRequest
            self.activeRecognitionTask = nil
            self.stateLock.unlock()

            self.beginMicrophoneRecognitionSegment(
                runId: runId,
                request: nextRequest,
                recognizer: recognizer,
                task: task
            )
        }
    }

    private func joinTranscript(_ prefix: String, _ segment: String) -> String {
        [prefix, segment]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func beginRecognition(
        runId: String,
        request: SFSpeechRecognitionRequest,
        recognizer: SFSpeechRecognizer,
        task: BGContinuedProcessingTask
    ) {
        task.progress.completedUnitCount = 25
        task.updateTitle("Transcribing validation audio", subtitle: "Speech recognition is running")
        update(runId: runId, phase: .transcribing, progress: 25)

        let recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let transcript = result.bestTranscription.formattedString
                let currentProgress = self.store.load().progressPercent
                let progress = result.isFinal ? 100 : max(currentProgress, 65)
                task.progress.completedUnitCount = Int64(progress)
                self.update(runId: runId, phase: .transcribing, progress: progress, transcript: transcript)
                if result.isFinal {
                    self.complete(runId: runId, transcript: transcript)
                }
            } else if let error {
                self.fail(runId: runId, message: "Speech recognition failed: \(error.localizedDescription)")
            }
        }
        stateLock.lock()
        activeRecognitionTask = recognitionTask
        stateLock.unlock()
    }

    private func scheduleMicrophoneProgress(run: TranscriptionRun, task: BGContinuedProcessingTask) {
        for second in 1...run.expectedDurationSeconds {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(second)) { [weak self] in
                guard let self, !self.isCancelled(run.id) else { return }
                let progress = min(88, 25 + (second * 63 / run.expectedDurationSeconds))
                task.progress.completedUnitCount = Int64(progress)
                self.update(runId: run.id, phase: .transcribing, progress: progress)
            }
        }

        let finishWorkItem = DispatchWorkItem { [weak self] in
            self?.finishMicrophoneInput(runId: run.id, task: task)
        }
        stateLock.lock()
        microphoneFinishWorkItem = finishWorkItem
        stateLock.unlock()
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .seconds(run.expectedDurationSeconds),
            execute: finishWorkItem
        )
    }

    private func finishMicrophoneInput(runId: String, task: BGContinuedProcessingTask) {
        guard !isCancelled(runId) else { return }
        stateLock.lock()
        let engine = activeAudioEngine
        let request = activeBufferRequest
        activeAudioEngine = nil
        microphoneFinishWorkItem = nil
        microphoneIsFinishing = true
        stateLock.unlock()

        if engine != nil {
            engine?.stop()
            engine?.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        task.progress.completedUnitCount = 90
        task.updateTitle("Transcribing live microphone", subtitle: "Finalizing transcript")
        update(runId: runId, phase: .transcribing, progress: 90)

        let finalizationWorkItem = DispatchWorkItem { [weak self] in
            guard let self, !self.store.load().phase.isTerminal else { return }
            let transcript = self.store.load().transcript
            if transcript.isEmpty {
                self.fail(runId: runId, message: "Speech recognition did not return a transcript after microphone capture ended.")
            } else {
                self.complete(runId: runId, transcript: transcript)
            }
        }
        stateLock.lock()
        microphoneFinalizationWorkItem = finalizationWorkItem
        stateLock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(10), execute: finalizationWorkItem)
    }

    private func update(
        runId: String,
        phase: TranscriptionPhase,
        progress: Int,
        transcript: String? = nil
    ) {
        guard let run = store.update(id: runId, {
            $0.phase = phase
            $0.progressPercent = progress
            if let transcript { $0.transcript = transcript }
        }) else { return }
        AnsightTelemetry.record("background_transcription.phase.\(phase.rawValue)", run: run)
    }

    private func complete(runId: String, transcript: String) {
        guard let run = store.update(id: runId, {
            $0.phase = .completed
            $0.progressPercent = 100
            $0.transcript = transcript
        }) else { return }
        AnsightTelemetry.record("background_transcription.completed", run: run)
        finishBackgroundTask(success: true)
    }

    private func fail(runId: String, message: String) {
        guard let run = store.update(id: runId, {
            $0.phase = .failed
            $0.error = message
        }) else { return }
        AnsightTelemetry.record("background_transcription.failed", run: run)
        finishBackgroundTask(success: false)
    }

    private func expire(runId: String) {
        stateLock.lock()
        cancelledRunIds.insert(runId)
        let recognitionTask = activeRecognitionTask
        activeRecognitionTask = nil
        stateLock.unlock()
        recognitionTask?.cancel()
        guard let run = store.update(id: runId, {
            $0.phase = .expired
            $0.error = "The system expired the continued-processing task."
        }) else { return }
        AnsightTelemetry.record("background_transcription.expired", run: run)
        finishBackgroundTask(success: false)
    }

    private func interruptPersistedRun(_ run: TranscriptionRun, reason: String) {
        guard let interruptedRun = store.update(id: run.id, {
            $0.phase = .interrupted
            $0.error = reason
        }) else { return }
        AnsightTelemetry.record("background_transcription.interrupted", run: interruptedRun)
    }

    private func taskIdentifier(for runId: String) -> String {
        "\(Self.taskIdentifierPrefix).\(runId)"
    }

    private func finishBackgroundTask(success: Bool) {
        stopMicrophoneCapture(endAudio: true)
        stateLock.lock()
        let task = activeBackgroundTask
        activeBackgroundTask = nil
        activeRecognitionTask = nil
        stateLock.unlock()
        completeAfterArtifactCaptureWindow(task, success: success)
    }

    private func completeAfterArtifactCaptureWindow(
        _ task: BGContinuedProcessingTask?,
        success: Bool
    ) {
        guard let task else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .seconds(3)) {
            task.setTaskCompleted(success: success)
        }
    }

    private func stopMicrophoneCapture(endAudio: Bool) {
        stateLock.lock()
        let engine = activeAudioEngine
        let request = activeBufferRequest
        let finishWorkItem = microphoneFinishWorkItem
        let finalizationWorkItem = microphoneFinalizationWorkItem
        activeAudioEngine = nil
        activeBufferRequest = nil
        microphoneFinishWorkItem = nil
        microphoneFinalizationWorkItem = nil
        microphoneTranscriptPrefix = ""
        microphoneIsFinishing = false
        stateLock.unlock()

        finishWorkItem?.cancel()
        finalizationWorkItem?.cancel()
        if engine != nil {
            engine?.stop()
            engine?.inputNode.removeTap(onBus: 0)
        }
        if endAudio {
            request?.endAudio()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func isCancelled(_ runId: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cancelledRunIds.contains(runId)
    }

    private func saveImmediateFailure(
        _ message: String,
        duration: RecordingDuration,
        source: TranscriptionSource
    ) {
        let fixtureFileName = source == .deviceMicrophone
            ? "device-microphone"
            : duration.injectedFixtureFileName ?? "none"
        let run = TranscriptionRun(
            id: UUID().uuidString,
            platform: "iOS",
            audioSource: source.rawValue,
            fixtureFileName: fixtureFileName,
            expectedDurationSeconds: duration.durationSeconds,
            startedAt: Date(),
            updatedAt: Date(),
            phase: .failed,
            progressPercent: 0,
            backgroundedDuringRun: false,
            transcript: "",
            error: message
        )
        store.save(run)
        AnsightTelemetry.record("background_transcription.failed", run: run)
    }
}
