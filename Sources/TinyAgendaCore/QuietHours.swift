import Foundation

/// Pure function for the "is this date inside the user's quiet hours?" decision.
///
/// Extracted from `NotificationManager` so it can be unit-tested without linking AppKit or
/// `UserNotifications`. Hours are Int in `0...23`; supports both daytime ranges
/// (e.g. 9→17) and overnight ranges (e.g. 22→7). `startHour == endHour` disables quiet hours.
public enum QuietHours {
    /// Returns `true` when the hour component of `date` (in the supplied calendar) falls inside
    /// the `[startHour, endHour)` range.
    ///
    /// - Parameters:
    ///   - date: Instant to test.
    ///   - startHour: Inclusive start hour, `0...23`.
    ///   - endHour: Exclusive end hour, `0...23`.
    ///   - calendar: Calendar used to extract the hour component. Defaults to `.current`; tests
    ///     inject a fixed calendar so results don't depend on the host timezone.
    public static func contains(
        _ date: Date,
        startHour: Int,
        endHour: Int,
        calendar: Calendar = .current
    ) -> Bool {
        let hour = calendar.component(.hour, from: date)
        if startHour == endHour { return false }
        if startHour < endHour {
            return hour >= startHour && hour < endHour
        }
        // Overnight: e.g. 22→7 covers hours [22, 24) ∪ [0, 7).
        return hour >= startHour || hour < endHour
    }
}
