@testable import TinyAgendaCore
import Foundation
import XCTest

final class ICSParserTests: XCTestCase {
    func testParseDurationValue() {
        XCTAssertEqual(ICSParser.parseDurationValue("PT1H30M"), 5400)
        XCTAssertEqual(ICSParser.parseDurationValue("PT45M"), 2700)
        XCTAssertEqual(ICSParser.parseDurationValue("P1DT2H"), 86400 + 7200)
        XCTAssertNil(ICSParser.parseDurationValue("-PT1H"))
    }

    func testDurationOnlyEventEndTime() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:dur@test
        DTSTART:20260420T100000Z
        DURATION:PT1H30M
        SUMMARY:Meeting
        END:VEVENT
        END:VCALENDAR
        """
        let now = try XCTUnwrap(isoDate("20260415T120000Z"))
        let events = ICSParser.parse(ics, now: now, horizonDays: 365)
        XCTAssertEqual(events.count, 1)
        let ev = try XCTUnwrap(events.first)
        XCTAssertEqual(ev.end.timeIntervalSince(ev.start), 5400, accuracy: 0.001)
    }

    func testExdateRemovesRecurrenceInstance() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:ex@test
        DTSTART:20260410T100000Z
        RRULE:FREQ=DAILY;COUNT=5
        EXDATE:20260412T100000Z
        SUMMARY:Daily
        END:VEVENT
        END:VCALENDAR
        """
        let now = isoDate("20260409T120000Z")!
        let events = ICSParser.parse(ics, now: now, horizonDays: 60)
        let starts = events.map(\.start).sorted { $0 < $1 }
        let day10 = isoDate("20260410T100000Z")!
        let day11 = isoDate("20260411T100000Z")!
        let day12 = isoDate("20260412T100000Z")!
        let day13 = isoDate("20260413T100000Z")!
        let day14 = isoDate("20260414T100000Z")!
        XCTAssertTrue(starts.contains(day10))
        XCTAssertTrue(starts.contains(day11))
        XCTAssertFalse(starts.contains(day12))
        XCTAssertTrue(starts.contains(day13))
        XCTAssertTrue(starts.contains(day14))
    }

    func testWeeklyByDayMoWe() throws {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:byday@test
        DTSTART:20260413T140000Z
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE;INTERVAL=1
        SUMMARY:Standup
        END:VEVENT
        END:VCALENDAR
        """
        let now = isoDate("20260410T120000Z")!
        let events = ICSParser.parse(ics, now: now, horizonDays: 21)
        let starts = Set(events.map(\.start))
        let mon1 = isoDate("20260413T140000Z")!
        let wed1 = isoDate("20260415T140000Z")!
        let mon2 = isoDate("20260420T140000Z")!
        XCTAssertTrue(starts.contains(mon1))
        XCTAssertTrue(starts.contains(wed1))
        XCTAssertTrue(starts.contains(mon2))
        let tue = isoDate("20260414T140000Z")!
        XCTAssertFalse(starts.contains(tue))
    }

    private func isoDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.date(from: s)
    }
}
