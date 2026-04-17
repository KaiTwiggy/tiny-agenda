import Foundation
import ServiceManagement

/// Registers this app to launch at user login via `SMAppService` (macOS 13+).
/// Requires running from a real `.app` bundle (same constraint as notifications).
enum LaunchAtLogin {
    /// Alias so `@AppStorage(LaunchAtLogin.userPreferenceKey)` call sites don't have to spell
    /// out `Defaults.LaunchAtLogin.openAtLogin`. Real key lives in `Defaults.swift`.
    static let userPreferenceKey = Defaults.LaunchAtLogin.openAtLogin

    static var persistedUserWantsOpenAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: userPreferenceKey) }
        set { UserDefaults.standard.set(newValue, forKey: userPreferenceKey) }
    }

    /// `SMAppService` only works for a normal application bundle.
    static var isSupported: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// Seed UserDefaults from the login item state once (existing installs before this key existed).
    @available(macOS 13.0, *)
    static func migratePreferenceFromServiceIfNeeded() {
        guard isSupported else { return }
        guard UserDefaults.standard.object(forKey: userPreferenceKey) == nil else { return }
        persistedUserWantsOpenAtLogin = isRegistered
    }

    /// Re-register if the user chose “open at login” but the system list was cleared (updates, revokes).
    @available(macOS 13.0, *)
    static func applyPersistedPreferenceAtLaunch() {
        guard isSupported else { return }
        guard persistedUserWantsOpenAtLogin else { return }
        guard !isRegistered else { return }
        try? setEnabled(true)
    }

    @available(macOS 13.0, *)
    static var serviceStatus: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// Reflects whether login-item registration is active (user may still need to approve in System Settings).
    @available(macOS 13.0, *)
    static var isRegistered: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    @available(macOS 13.0, *)
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    @available(macOS 13.0, *)
    static var statusHint: String? {
        switch SMAppService.mainApp.status {
        case .requiresApproval:
            return "Open System Settings → General → Login Items and allow TinyAgenda."
        case .notFound:
            return "App not found for login registration. Run from TinyAgenda.app."
        case .enabled, .notRegistered:
            return nil
        @unknown default:
            return nil
        }
    }
}
