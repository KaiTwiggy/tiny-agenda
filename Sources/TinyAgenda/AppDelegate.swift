import AppKit
import os

extension Notification.Name {
    /// Opens the settings window via `SettingsLaunchBridge` (SwiftUI `openWindow`).
    static let openTinyAgendaSettings = Notification.Name("openTinyAgendaSettings")
}

private let log = Logger(subsystem: "tools.tinyagenda", category: "MenuBar")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = CalendarViewModel()
    private var statusBarController: MenuBarStatusItemController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SparkleCoordinator.shared.start()
        if #available(macOS 13.0, *) {
            LaunchAtLogin.migratePreferenceFromServiceIfNeeded()
            LaunchAtLogin.applyPersistedPreferenceAtLaunch()
        }
        // Defer past SwiftUI scene attachment; avoids rare cases where the status item never draws.
        DispatchQueue.main.async { [weak self] in
            self?.installStatusBarIfNeeded()
        }
    }

    private func installStatusBarIfNeeded() {
        if statusBarController != nil { return }
        statusBarController = MenuBarStatusItemController(viewModel: viewModel)
        statusBarController?.install()
        if statusBarController?.hasVisibleButton != true {
            log.error("Status item has no button after install; retrying once.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self else { return }
                self.statusBarController = nil
                self.statusBarController = MenuBarStatusItemController(viewModel: self.viewModel)
                self.statusBarController?.install()
                if self.statusBarController?.hasVisibleButton == true {
                    log.info("Status item installed on retry.")
                } else {
                    log.error("Status item still missing after retry — check menu bar overflow and all displays.")
                }
            }
        } else {
            log.info("Status item installed.")
        }
    }
}
