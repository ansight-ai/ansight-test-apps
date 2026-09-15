import Ansight
import Foundation

enum AnsightTelemetry {
    static let progressChannel = 40
    static let terminalEventLabel = "background_transcription.terminal"

    static func initialize() {
        do {
            var options = AnsightOptions.ansightDeveloperDefaults
            options.retentionPeriodSeconds = 300
            options.additionalChannels = [
                AnsightChannel(
                    id: progressChannel,
                    name: "Transcription Progress",
                    color: "#0A84FF",
                    unit: "%",
                    type: "progress",
                    source: "background-transcription"
                ),
            ]
            options.enableBatteryLevel = true
            options.enableOpenFileHandleTracking = true
            options.sessionJpegCapture = AnsightSessionJpegCaptureOptions(
                intervalMilliseconds: 1_000,
                quality: 60,
                maxWidth: 600,
                captureGpuBackedSurfaces: false,
                mode: .screenshotWithVisualTreeOnTouch
            )
            #if !DEBUG
            options.sessionJpegCapture = nil
            options.toolGuard = .disabled
            #endif
            options.customProperties = [
                "spike": [
                    "name": "background-transcription",
                    "platform": "ios-native",
                    "backgroundPrimitive": "BGContinuedProcessingTask",
                    "speechPrimitive": "SFSpeechURLRecognitionRequest",
                    "captureProfile": "full-development",
                ],
            ]

            try AnsightRuntime.shared.initializeAndActivateAnsightSdk(
                options: options,
                remoteToolOptions: AnsightRemoteToolOptions(
                    artifactProviders: [TranscriptionRunArtifactProvider()]
                )
            )
            try AnsightRuntime.shared.screenViewed(
                "Background Transcription Spike",
                details: ["route": "/background-transcription"]
            )
        } catch {
            NSLog("Ansight initialization failed: %@", error.localizedDescription)
        }
    }

    static func record(_ label: String, run: TranscriptionRun) {
        let details = [
            "schema": "ansight.background-transcription-terminal/v1",
            "runId": run.id,
            "platform": run.platform,
            "audioSource": run.audioSource ?? TranscriptionSource.injectedFixture.rawValue,
            "fixtureFileName": run.fixtureFileName,
            "expectedDurationSeconds": String(run.expectedDurationSeconds),
            "phase": run.phase.rawValue,
            "progressPercent": String(run.progressPercent),
            "backgroundedDuringRun": String(run.backgroundedDuringRun),
            "transcript": run.transcript,
            "error": run.error ?? "",
            "providerId": TranscriptionRunArtifactProvider.providerId,
            "resultArtifactId": TranscriptionRunArtifactProvider.artifactId,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: details, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return }
        do {
            try AnsightRuntime.shared.metric(Int64(run.progressPercent), channel: progressChannel)
            try AnsightRuntime.shared.event(
                label,
                type: run.phase == .failed || run.phase == .expired || run.phase == .interrupted ? .error : .info,
                details: json,
                externalId: run.id
            )
            if run.phase.isTerminal, label != terminalEventLabel {
                try AnsightRuntime.shared.event(
                    terminalEventLabel,
                    type: run.phase == .failed || run.phase == .expired || run.phase == .interrupted ? .error : .info,
                    details: json,
                    externalId: run.id
                )
            }
        } catch {
            NSLog("Ansight event failed: %@", error.localizedDescription)
        }

        let emittedLabels = run.phase.isTerminal && label != terminalEventLabel
            ? [label, terminalEventLabel]
            : [label]
        for emittedLabel in emittedLabels {
            let logLine = "\(emittedLabel) runId=\(run.id) phase=\(run.phase.rawValue) progress=\(run.progressPercent)%"
            NSLog("%@", logLine)
            Task {
                _ = await AnsightRuntime.shared.sendClientLog(logLine)
            }
        }
    }
}
