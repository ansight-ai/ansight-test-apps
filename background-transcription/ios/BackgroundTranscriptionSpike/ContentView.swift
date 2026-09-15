import SwiftUI

struct ContentView: View {
    @State private var run = RunStore.shared.load()
    @State private var selectedSource = TranscriptionSource.injectedFixture
    @State private var selectedDuration = RecordingDuration.sixtySeconds
    @StateObject private var enrollment = AnsightEnrollmentModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Injected speech starts after a 10-second backgrounding window. Device mic starts immediately: tap Start, speak, then background the app.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("background-transcription.instructions")

                    GroupBox("Ansight enrollment") {
                        VStack(alignment: .leading, spacing: 10) {
                            valueRow("State", enrollment.connectionState)
                            valueRow("Registration", enrollment.registration)
                            valueRow("Host", enrollment.hostName)

                            Button {
                                enrollment.scanEnrollmentQR()
                            } label: {
                                Label("Scan enrollment QR", systemImage: "qrcode.viewfinder")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(enrollment.isBusy)
                            .accessibilityIdentifier("background-transcription.enrollment.scan")

                            Button("Clear enrollment", role: .destructive) {
                                enrollment.clearEnrollment()
                            }
                            .disabled(enrollment.isBusy || !enrollment.hasEnrollment)
                            .accessibilityIdentifier("background-transcription.enrollment.clear")

                            if !enrollment.message.isEmpty {
                                Text(enrollment.message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("background-transcription.enrollment")

                    Picker("Audio source", selection: $selectedSource) {
                        ForEach(TranscriptionSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isRunActive)
                    .accessibilityIdentifier("background-transcription.source")

                    Picker("Recording duration", selection: $selectedDuration) {
                        ForEach(availableDurations) { duration in
                            Text(duration.title).tag(duration)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(isRunActive)
                    .accessibilityIdentifier("background-transcription.duration")

                    Button {
                        if isRunActive {
                            TranscriptionCoordinator.shared.cancelCurrentRun()
                        } else {
                            TranscriptionCoordinator.shared.requestAndSchedule(
                                duration: selectedDuration,
                                source: selectedSource
                            )
                        }
                    } label: {
                        Label(
                            isRunActive ? "Stop background transcription" : "Start background transcription",
                            systemImage: isRunActive ? "stop.fill" : "waveform.and.mic"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isRunActive ? .red : .accentColor)
                    .accessibilityIdentifier(
                        isRunActive
                            ? "background-transcription.stop"
                            : "background-transcription.start"
                    )

                    ProgressView(value: Double(run.progressPercent), total: 100)
                        .accessibilityIdentifier("background-transcription.progress")

                    GroupBox("Durable result") {
                        VStack(alignment: .leading, spacing: 10) {
                            valueRow("Phase", run.phase.rawValue)
                            valueRow("Progress", "\(run.progressPercent)%")
                            valueRow("Backgrounded", run.backgroundedDuringRun ? "yes" : "no")
                            valueRow("Audio source", run.audioSource ?? TranscriptionSource.injectedFixture.rawValue)
                            valueRow(
                                run.audioSource == TranscriptionSource.deviceMicrophone.rawValue ? "Input" : "Fixture",
                                run.audioSource == TranscriptionSource.deviceMicrophone.rawValue
                                    ? "Device microphone"
                                    : "\(run.fixtureFileName).wav"
                            )
                            valueRow("Audio duration", "\(run.expectedDurationSeconds)s")
                            valueRow("Run ID", run.id)
                            valueRow("Transcript", run.transcript.isEmpty ? "—" : run.transcript)
                            if let error = run.error {
                                valueRow("Error", error)
                                    .foregroundStyle(.red)
                            }
                            valueRow("Result file", RunStore.shared.resultURL.path)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(.body, design: .monospaced))
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("background-transcription.result")
                }
                .padding(24)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("background-transcription.content")
            }
            .navigationTitle("Background transcription")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onReceive(NotificationCenter.default.publisher(for: .transcriptionRunUpdated)) { _ in
            run = RunStore.shared.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            run = RunStore.shared.load()
            enrollment.refresh()
        }
        .onChange(of: selectedSource) { _, source in
            if source == .injectedFixture, !selectedDuration.supportsInjectedFixture {
                selectedDuration = .sixtySeconds
            }
        }
    }

    private var isRunActive: Bool {
        !run.phase.isTerminal && run.phase != .idle
    }

    private var availableDurations: [RecordingDuration] {
        switch selectedSource {
        case .injectedFixture:
            RecordingDuration.allCases.filter(\.supportsInjectedFixture)
        case .deviceMicrophone:
            RecordingDuration.allCases
        }
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}
