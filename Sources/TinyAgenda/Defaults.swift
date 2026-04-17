import Foundation

/// Single source of truth for every `UserDefaults` / `Info.plist` key TinyAgenda uses.
///
/// Motivation: scattered string literals make it easy to typo a key (silently falling back
/// to the default value) or to rename one call site without noticing the others. Everything
/// lives here so a rename touches exactly one line and `grep` on a key name finds its owner.
enum Defaults {
    /// Keys Sparkle itself reads/writes. Names mirror Sparkle's documented defaults.
    enum Sparkle {
        /// `UserDefaults` / `Info.plist` key for Sparkle's last check timestamp.
        static let lastCheckTime = "SULastCheckTime"
        /// `UserDefaults` / `Info.plist` key for automatic update checks.
        static let enableAutomaticChecks = "SUEnableAutomaticChecks"
        /// `Info.plist` key for the Sparkle EdDSA public key.
        static let publicEDKey = "SUPublicEDKey"
        /// `Info.plist` key for the Sparkle appcast feed URL.
        static let feedURL = "SUFeedURL"
    }

    /// Open-at-login toggle persistence.
    enum LaunchAtLogin {
        /// Stores the user's intent so Settings stays in sync even if `SMAppService` transiently
        /// reports a different state (e.g. right after a system update).
        static let openAtLogin = "openAtLoginUserPreference"
    }

    /// Calendar/menu-bar preferences owned by `CalendarViewModel`.
    enum Calendar {
        static let refreshInterval = "refreshInterval"
        static let leadMinutes = "leadMinutes"
        static let quietHoursEnabled = "quietHoursEnabled"
        static let quietStartHour = "quietStartHour"
        static let quietEndHour = "quietEndHour"
        static let menuBarVisibilityLeadMinutes = "menuBarVisibilityLeadMinutes"
        static let hiddenEventIds = "hiddenEventIds"
        static let omitTentativeEvents = "omitTentativeEvents"
        static let omitNeedsActionEvents = "omitNeedsActionEvents"
        static let menuBarIdleShowsText = "menuBarIdleShowsText"
        static let menuBarFadeOutMinutes = "menuBarFadeOutMinutes"
        static let toastNotificationsEnabled = "toastNotificationsEnabled"
    }
}

/// Back-compat alias. Prefer `Defaults.Sparkle` at new call sites.
typealias SparkleDefaults = Defaults.Sparkle
