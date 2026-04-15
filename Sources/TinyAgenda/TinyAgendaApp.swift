import AppKit
import SwiftUI

@main
struct TinyAgendaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Invisible anchor so `SettingsLaunchBridge` receives `openWindow` (popover uses AppKit hosting).
        Window("", id: "settingsBridge") {
            SettingsLaunchBridge()
        }
        .defaultSize(width: 1, height: 1)

        // A real `Window` opened via `openWindow(id:)` — `NSApp.sendAction(showSettingsWindow:)`
        // does not reach SwiftUI’s settings scene in LSUIElement / menu-bar-only apps.
        Window("TinyAgenda Settings", id: "settings") {
            SettingsView(viewModel: appDelegate.viewModel)
        }
        .defaultSize(width: 480, height: 560)
    }
}
