import AppKit
import SwiftUI

@main
struct LiveSubsApp: App {
    @NSApplicationDelegateAdaptor(LiveSubsAppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 560, minHeight: 440)
        }
        .windowResizability(.contentSize)
    }
}

final class LiveSubsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        OfflineSubtitleEngine.shared.stop()
    }
}
