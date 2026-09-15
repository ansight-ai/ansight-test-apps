import UIKit

final class SpikeAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AnsightTelemetry.initialize()
        TranscriptionCoordinator.shared.reconcilePersistedRunOnLaunch()
        return true
    }
}
