import SwiftUI

@main
struct BackgroundTranscriptionSpikeApp: App {
    @UIApplicationDelegateAdaptor(SpikeAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                TranscriptionCoordinator.shared.markApplicationBackgrounded()
            }
        }
    }
}
