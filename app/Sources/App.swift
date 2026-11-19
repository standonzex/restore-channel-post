#if os(macOS)
import SwiftUI
import AppKit

final class DemoAppDelegate: NSObject, NSApplicationDelegate {
    var host: DemoHost?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { host?.stop() }
}
@main struct ChannelRecoveryApplication: App {
    @NSApplicationDelegateAdaptor(DemoAppDelegate.self) private var delegate
    @StateObject private var model = RecoveryViewModel()
    var body: some Scene {
        Window("Restore Channel Post — Reference Build", id: "recovery") {
            RecoveryView(model: model).preferredColorScheme(.light)
                .task { delegate.host = model.host; await model.start(); await model.poll() }
        }.defaultSize(width: 1020, height: 780)
    }
}
#endif
