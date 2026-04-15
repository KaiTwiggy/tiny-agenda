import SwiftUI

/// Holds `openWindow` from the SwiftUI scene graph so menu/popover content can request Settings via `NotificationCenter` (NSHostingController does not get `EnvironmentValues.openWindow`).
struct SettingsLaunchBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onReceive(NotificationCenter.default.publisher(for: .openTinyAgendaSettings)) { _ in
                openWindow(id: "settings")
            }
    }
}
