import Ansight
import Foundation

@MainActor
final class AnsightEnrollmentModel: ObservableObject {
    @Published private(set) var snapshot = AnsightRuntime.shared.snapshot()
    @Published private(set) var isBusy = false
    @Published private(set) var message = ""

    var connectionState: String {
        snapshot.hostConnectionStatus.summaryMessage
    }

    var registration: String {
        snapshot.lastPairingConfigId ?? "Not enrolled"
    }

    var hostName: String {
        snapshot.hostConnectionStatus.hostName ?? "No connected host"
    }

    var hasEnrollment: Bool {
        snapshot.hostConnectionStatus.hasSavedConfig || snapshot.lastPairingConfigId != nil
    }

    func refresh() {
        snapshot = AnsightRuntime.shared.snapshot()
    }

    func scanEnrollmentQR() {
        guard !isBusy else { return }
        isBusy = true
        message = "Opening Ansight QR scanner…"

        Task { @MainActor in
            let result = await AnsightRuntime.shared.connect(
                .qrCode(
                    title: "Scan Ansight Enrollment QR",
                    clientName: "Background Transcription iOS"
                )
            )
            message = result.message
            isBusy = false
            refresh()
        }
    }

    func clearEnrollment() {
        AnsightRuntime.shared.clearSavedPairing()
        AnsightRuntime.shared.clearCachedSession()
        message = "Saved enrollment and cached session cleared."
        refresh()
    }
}
