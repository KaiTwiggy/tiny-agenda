import TinyAgendaCore
import Foundation
import XCTest

final class QuietHoursTests: XCTestCase {
    /// Tests pin a fixed calendar in a stable timezone so `Calendar.component(.hour, from:)`
    /// doesn't depend on the host machine's locale/DST state.
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func date(hour: Int) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 4
        comps.day = 17
        comps.hour = hour
        comps.minute = 30
        return calendar.date(from: comps)!
    }

    // MARK: - Degenerate ranges

    func testStartEqualsEndDisablesQuietHours() {
        for h in 0...23 {
            XCTAssertFalse(
                QuietHours.contains(date(hour: h), startHour: 10, endHour: 10, calendar: calendar),
                "hour \(h) should never be in a start==end range"
            )
        }
    }

    // MARK: - Daytime ranges (start < end)

    func testDaytimeRangeIncludesHoursInsideHalfOpenInterval() {
        // 9:30 AM → 5:30 PM quiet; 9→17.
        XCTAssertTrue(QuietHours.contains(date(hour: 9), startHour: 9, endHour: 17, calendar: calendar))
        XCTAssertTrue(QuietHours.contains(date(hour: 12), startHour: 9, endHour: 17, calendar: calendar))
        XCTAssertTrue(QuietHours.contains(date(hour: 16), startHour: 9, endHour: 17, calendar: calendar))
    }

    func testDaytimeRangeExcludesBoundaryAndOutside() {
        // Half-open: hour == endHour is *outside* (notifications fire at exactly 17:00).
        XCTAssertFalse(QuietHours.contains(date(hour: 17), startHour: 9, endHour: 17, calendar: calendar))
        XCTAssertFalse(QuietHours.contains(date(hour: 8), startHour: 9, endHour: 17, calendar: calendar))
        XCTAssertFalse(QuietHours.contains(date(hour: 23), startHour: 9, endHour: 17, calendar: calendar))
    }

    // MARK: - Overnight ranges (start > end)

    func testOvernightRangeCoversBothSidesOfMidnight() {
        // 22:00 → 07:00 quiet: covers [22, 24) ∪ [0, 7).
        XCTAssertTrue(QuietHours.contains(date(hour: 22), startHour: 22, endHour: 7, calendar: calendar))
        XCTAssertTrue(QuietHours.contains(date(hour: 23), startHour: 22, endHour: 7, calendar: calendar))
        XCTAssertTrue(QuietHours.contains(date(hour: 0), startHour: 22, endHour: 7, calendar: calendar))
        XCTAssertTrue(QuietHours.contains(date(hour: 6), startHour: 22, endHour: 7, calendar: calendar))
    }

    func testOvernightRangeExcludesDaytimeAndEndBoundary() {
        XCTAssertFalse(QuietHours.contains(date(hour: 7), startHour: 22, endHour: 7, calendar: calendar))
        XCTAssertFalse(QuietHours.contains(date(hour: 12), startHour: 22, endHour: 7, calendar: calendar))
        XCTAssertFalse(QuietHours.contains(date(hour: 21), startHour: 22, endHour: 7, calendar: calendar))
    }

    // MARK: - One-hour ranges

    func testSingleHourRangeOnlyCoversOneHour() {
        // 13:00 → 14:00 quiet.
        XCTAssertTrue(QuietHours.contains(date(hour: 13), startHour: 13, endHour: 14, calendar: calendar))
        XCTAssertFalse(QuietHours.contains(date(hour: 14), startHour: 13, endHour: 14, calendar: calendar))
        XCTAssertFalse(QuietHours.contains(date(hour: 12), startHour: 13, endHour: 14, calendar: calendar))
    }
}
