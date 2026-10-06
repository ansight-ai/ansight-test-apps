import UIKit
#if DEBUG
import Ansight
#endif

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        #if DEBUG
        do {
            try AnsightRuntime.shared.initializeAndActivateAnsightSdk()
        } catch {
            NSLog("Ansight initialization failed: %@", error.localizedDescription)
        }
        #endif

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = MotionViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
