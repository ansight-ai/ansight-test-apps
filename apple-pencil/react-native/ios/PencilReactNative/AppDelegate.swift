import UIKit
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var factory: RCTReactNativeFactory?
    var delegate: PencilDelegate?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // This drawing app uses RN pointer callbacks for ordinary input too.
        RCTSetDispatchW3CPointerEvents(true)
        let delegate = PencilDelegate()
        delegate.dependencyProvider = RCTAppDependencyProvider()
        self.delegate = delegate
        let factory = RCTReactNativeFactory(delegate: delegate)
        self.factory = factory
        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        factory.startReactNative(withModuleName: "PencilReactNative", in: window, launchOptions: launchOptions)
        return true
    }
}
class PencilDelegate: RCTDefaultReactNativeFactoryDelegate {
    override func sourceURL(for bridge: RCTBridge) -> URL? { bundleURL() }
    override func bundleURL() -> URL? { Bundle.main.url(forResource: "main", withExtension: "jsbundle") }
}
