import Foundation

public enum ICSParser {
    /// RFC 5545 `DURATION` value → seconds. Returns `nil` if unsupported or invalid.
    static func parseDurationValue(_ rawLineOrValue: String) -> TimeInterval? {
        let v: String = {
            if rawLineOrValue.contains(":") {
                return propertyValue(rawLineOrValue).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return rawLineOrValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        if v.hasPrefix("-") { return nil }
        var s = v.hasPrefix("+") ? String(v.dropFirst()) : v
        guard s.hasPrefix("P") else { return nil }
        s.removeFirst()
        var total: Double = 0
        if let tIdx = s.firstIndex(of: "T") {
            let datePart = String(s[..<tIdx])
            let timePart = String(s[s.index(after: tIdx)...])
            total += parseDurationDatePart(datePart)
            total += parseDurationTimePart(timePart)
        } else {
            total += parseDurationDatePart(s)
        }
        return total > 0 ? total : nil
    }

    private static func parseDurationDatePart(_ part: String) -> Double {
        guard !part.isEmpty else { return 0 }
        var sum: Double = 0
        var num = ""
        for ch in part {
            if ch.isNumber {
                num.append(ch)
            } else if ch == "W" {
                if let n = Int(num) { sum += Double(n) * 7 * 86400 }
                num = ""
            } else if ch == "D" {
                if let n = Int(num) { sum += Double(n) * 86400 }
                num = ""
            } else {
                num = ""
            }
        }
        return sum
    }

    private static func parseDurationTimePart(_ part: String) -> Double {
        guard !part.isEmpty else { return 0 }
        var sum: Double = 0
        var num = ""
        for ch in part {
            if ch.isNumber {
                num.append(ch)
            } else if ch == "H" {
                if let n = Int(num) { sum += Double(n) * 3600 }
                num = ""
            } else if ch == "M" {
                if let n = Int(num) { sum += Double(n) * 60 }
                num = ""
            } else if ch == "S" {
                if let n = Int(num) { sum += Double(n) }
                num = ""
            } else {
                num = ""
            }
        }
        return sum
    }

    public static func parse(_ ics: String, now: Date = Date(), horizonDays: Int = 14) -> [CalendarEvent] {
        let lines = unfoldLines(ics)
        let blocks = extractVEvents(lines: lines)
        var out: [CalendarEvent] = []
        let horizonEnd = Calendar.current.date(byAdding: .day, value: horizonDays, to: now) ?? now.addingTimeInterval(Double(horizonDays * 86400))
        let windowStart = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now

        for block in blocks {
            if block.count > 5000 { continue }
            let participation = parseParticipation(block)
            let props = parseProperties(block)
            guard let dtstart = props["DTSTART"] else { continue }
            let uid: String = {
                guard let raw = props["UID"] else { return UUID().uuidString }
                let v = propertyValue(raw)
                return v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString : v
            }()
            let summary = unescapeICS(props["SUMMARY"].map(propertyValue) ?? "")
            let desc = unescapeICS(props["DESCRIPTION"].map(propertyValue) ?? "")
            let loc = unescapeICS(props["LOCATION"].map(propertyValue) ?? "")
            let rrule = props["RRULE"]

            let startInfo = parseDateProperty(dtstart)
            var endInfo: DateComponentsResult?
            var durationSeconds: TimeInterval?
            if let dtend = props["DTEND"] {
                endInfo = parseDateProperty(dtend)
            } else if let dur = props["DURATION"] {
                endInfo = nil
                durationSeconds = parseDurationValue(dur)
            }

            let exdates = parseEXDATEs(block: block, dtstartSample: dtstart)

            if let rrule = rrule, !rrule.isEmpty {
                let instances = RecurrenceExpander.instances(
                    uid: uid,
                    dtstart: startInfo,
                    dtend: endInfo,
                    durationFromICS: durationSeconds,
                    rrule: rrule,
                    summary: summary,
                    description: desc,
                    location: loc,
                    participation: participation,
                    windowStart: windowStart,
                    windowEnd: horizonEnd,
                    excluded: exdates
                )
                out.append(contentsOf: instances)
            } else {
                guard let startDate = startInfo.date else { continue }
                let endDate: Date
                if let e = endInfo?.date {
                    endDate = e
                } else if let d = durationSeconds {
                    endDate = startDate.addingTimeInterval(d)
                } else {
                    endDate = startInfo.isAllDay
                        ? Calendar.current.startOfDay(for: startDate).addingTimeInterval(86400)
                        : startDate.addingTimeInterval(3600)
                }
                if endDate < windowStart || startDate > horizonEnd { continue }
                if isExcluded(start: startDate, allDay: startInfo.isAllDay, excluded: exdates) { continue }
                let ev = makeEvent(
                    uid: uid,
                    start: startDate,
                    end: endDate,
                    title: summary,
                    description: desc,
                    location: loc,
                    isAllDay: startInfo.isAllDay,
                    participation: participation
                )
                out.append(ev)
            }
        }

        return out.sorted { $0.start < $1.start }
    }

    private static func isExcluded(start: Date, allDay: Bool, excluded: Set<Date>) -> Bool {
        guard !excluded.isEmpty else { return false }
        let cal = Calendar.current
        for ex in excluded {
            if allDay {
                if cal.isDate(start, inSameDayAs: ex) { return true }
            } else {
                if abs(ex.timeIntervalSince(start)) < 0.5 { return true }
            }
        }
        return false
    }

    /// Collect EXDATE instants from all `EXDATE` lines in the block.
    private static func parseEXDATEs(block: [String], dtstartSample: String) -> Set<Date> {
        let dtParams = splitParamsAndValue(dtstartSample).0
        let defaultTz = dtParams["TZID"].flatMap { TimeZone(identifier: $0) }
        var set = Set<Date>()
        for line in block {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let namePart = String(parts[0])
            guard namePart.uppercased().hasPrefix("EXDATE") else { continue }
            let (params, valueStr) = splitParamsAndValue(line)
            let tz = params["TZID"].flatMap { TimeZone(identifier: $0) } ?? defaultTz
            for piece in valueStr.split(separator: ",") {
                let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if params["VALUE"]?.uppercased() == "DATE" || (trimmed.count == 8 && !trimmed.contains("T")) {
                    if let d = parseDateOnly(String(trimmed.prefix(8))) { set.insert(d) }
                } else {
                    if let d = parseDateTime(String(trimmed), tz: tz) { set.insert(d) }
                }
            }
        }
        return set
    }

    private static func makeEvent(
        uid: String,
        start: Date,
        end: Date,
        title: String,
        description: String,
        location: String,
        isAllDay: Bool,
        participation: EventParticipation
    ) -> CalendarEvent {
        let id = "\(uid)|\(Int(start.timeIntervalSince1970))"
        return CalendarEvent(
            id: id,
            uid: uid,
            start: start,
            end: end,
            title: title,
            description: description,
            location: location,
            isAllDay: isAllDay,
            isStatusTentative: participation.isStatusTentative,
            hasNeedsActionAttendee: participation.hasNeedsActionAttendee,
            hasTentativeAttendee: participation.hasTentativeAttendee
        )
    }

    struct EventParticipation: Equatable {
        var isStatusTentative: Bool = false
        var hasNeedsActionAttendee: Bool = false
        var hasTentativeAttendee: Bool = false
    }

    private static func parseParticipation(_ block: [String]) -> EventParticipation {
        var p = EventParticipation()
        for line in block {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let namePart = String(parts[0])
            let nameUpper = namePart.uppercased()
            if nameUpper.hasPrefix("STATUS") {
                let v = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                p.isStatusTentative = (v == "TENTATIVE")
            } else if nameUpper.hasPrefix("ATTENDEE") {
                let params = nameUpper
                if params.contains("PARTSTAT=NEEDS-ACTION") {
                    p.hasNeedsActionAttendee = true
                }
                if params.contains("PARTSTAT=TENTATIVE") {
                    p.hasTentativeAttendee = true
                }
            }
        }
        return p
    }

    struct DateComponentsResult {
        let date: Date?
        let isAllDay: Bool
        let tz: TimeZone?
    }

    private static func parseDateProperty(_ raw: String) -> DateComponentsResult {
        let (params, value) = splitParamsAndValue(raw)
        if params["VALUE"]?.uppercased() == "DATE" || (value.count == 8 && !value.contains("T")) {
            let d = parseDateOnly(value)
            return DateComponentsResult(date: d, isAllDay: true, tz: nil)
        }
        let tzName = params["TZID"].flatMap { TimeZone(identifier: $0) }
        let d = parseDateTime(value, tz: tzName)
        return DateComponentsResult(date: d, isAllDay: false, tz: tzName)
    }

    private static func parseDateOnly(_ value: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyyMMdd"
        return f.date(from: String(value.prefix(8)))
    }

    private static func parseDateTime(_ value: String, tz: TimeZone?) -> Date? {
        var v = value
        let isZ = v.hasSuffix("Z")
        if isZ { v.removeLast() }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        if isZ {
            f.timeZone = TimeZone(secondsFromGMT: 0)
        } else if let tz {
            f.timeZone = tz
        } else {
            f.timeZone = TimeZone.current
        }
        if v.count >= 15 {
            f.dateFormat = "yyyyMMdd'T'HHmmss"
            let idx = v.index(v.startIndex, offsetBy: 15)
            let base = String(v[..<idx])
            return f.date(from: base)
        }
        f.dateFormat = "yyyyMMdd"
        return f.date(from: String(v.prefix(8)))
    }

    private static func splitParamsAndValue(_ raw: String) -> ([String: String], String) {
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return ([:], raw) }
        let left = String(parts[0])
        let value = String(parts[1])
        var params: [String: String] = [:]
        let segs = left.split(separator: ";")
        for (i, seg) in segs.enumerated() {
            if i == 0 { continue }
            if let eq = seg.firstIndex(of: "=") {
                let k = String(seg[..<eq]).uppercased()
                let val = String(seg[seg.index(after: eq)...])
                params[k] = val
            }
        }
        return (params, value)
    }

    private static func parseProperties(_ lines: [String]) -> [String: String] {
        var dict: [String: String] = [:]
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let namePart = String(parts[0])
            let val = String(parts[1])
            let key = namePart.split(separator: ";").first.map { String($0).uppercased() } ?? ""
            if ["DTSTART", "DTEND", "SUMMARY", "DESCRIPTION", "LOCATION", "UID", "RRULE", "DURATION"].contains(key) {
                dict[key] = namePart + ":" + val
            }
        }
        return dict
    }

    /// Value only (after first `:`), for UID and text fields stored as full property lines.
    private static func propertyValue(_ fullLine: String) -> String {
        if let idx = fullLine.firstIndex(of: ":") {
            return String(fullLine[fullLine.index(after: idx)...])
        }
        return fullLine
    }

    private static func unfoldLines(_ raw: String) -> [String] {
        var result: [String] = []
        var current = ""
        for line in raw.components(separatedBy: .newlines) {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                current += String(line.dropFirst())
            } else {
                if !current.isEmpty { result.append(current) }
                current = line
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func extractVEvents(lines: [String]) -> [[String]] {
        var events: [[String]] = []
        var i = 0
        while i < lines.count {
            if lines[i].uppercased() == "BEGIN:VEVENT" {
                var block: [String] = []
                i += 1
                while i < lines.count && lines[i].uppercased() != "END:VEVENT" {
                    block.append(lines[i])
                    i += 1
                }
                events.append(block)
            }
            i += 1
        }
        return events
    }

    private static func unescapeICS(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}

// MARK: - Recurrence (limited)

private enum RecurrenceExpander {
    static func instances(
        uid: String,
        dtstart: ICSParser.DateComponentsResult,
        dtend: ICSParser.DateComponentsResult?,
        durationFromICS: TimeInterval?,
        rrule: String,
        summary: String,
        description: String,
        location: String,
        participation: ICSParser.EventParticipation,
        windowStart: Date,
        windowEnd: Date,
        excluded: Set<Date>
    ) -> [CalendarEvent] {
        guard let anchor = dtstart.date else { return [] }
        let rule = parseRRULE(rrule)
        let duration: TimeInterval
        if let e = dtend?.date {
            duration = max(e.timeIntervalSince(anchor), 60)
        } else if let d = durationFromICS, d > 0 {
            duration = max(d, 60)
        } else {
            duration = dtstart.isAllDay ? 86400 : 3600
        }

        var dates: [Date] = []
        let cal = Calendar.current

        if rule.freq == "DAILY" {
            var d = anchor
            let interval = max(rule.interval, 1)
            var occurrenceCount = 0
            var iterations = 0
            while d <= windowEnd && iterations < 400 {
                iterations += 1
                if d >= windowStart {
                    dates.append(d)
                    occurrenceCount += 1
                    if let c = rule.count, occurrenceCount >= c { break }
                }
                guard let next = cal.date(byAdding: .day, value: interval, to: d) else { break }
                d = next
                if let u = rule.until, d > u { break }
            }
        } else if rule.freq == "WEEKLY" {
            let interval = max(rule.interval, 1)
            if rule.byWeekday.isEmpty {
                var d = anchor
                var occurrenceCount = 0
                var iterations = 0
                while d <= windowEnd && iterations < 400 {
                    iterations += 1
                    if d >= windowStart {
                        dates.append(d)
                        occurrenceCount += 1
                        if let c = rule.count, occurrenceCount >= c { break }
                    }
                    guard let next = cal.date(byAdding: .weekOfYear, value: interval, to: d) else { break }
                    d = next
                    if let u = rule.until, d > u { break }
                }
            } else {
                dates = weeklyByDayOccurrences(
                    anchor: anchor,
                    windowStart: windowStart,
                    windowEnd: windowEnd,
                    interval: interval,
                    weekdays: rule.byWeekday,
                    timeFromAnchor: anchor,
                    until: rule.until,
                    count: rule.count,
                    calendar: cal
                )
            }
        } else {
            if anchor <= windowEnd && anchor >= windowStart.subtractingTimeInterval(86400) {
                dates = [anchor]
            }
        }

        return dates.compactMap { s -> CalendarEvent? in
            if isExcluded(start: s, allDay: dtstart.isAllDay, excluded: excluded) { return nil }
            let e = s.addingTimeInterval(duration)
            return CalendarEvent(
                id: "\(uid)|\(Int(s.timeIntervalSince1970))",
                uid: uid,
                start: s,
                end: e,
                title: summary,
                description: description,
                location: location,
                isAllDay: dtstart.isAllDay,
                isStatusTentative: participation.isStatusTentative,
                hasNeedsActionAttendee: participation.hasNeedsActionAttendee,
                hasTentativeAttendee: participation.hasTentativeAttendee
            )
        }
    }

    /// Swift `weekday`: 1=Sunday … 7=Saturday. `byWeekday` uses same numbering.
    private static func weeklyByDayOccurrences(
        anchor: Date,
        windowStart: Date,
        windowEnd: Date,
        interval: Int,
        weekdays: [Int],
        timeFromAnchor: Date,
        until: Date?,
        count: Int?,
        calendar: Calendar
    ) -> [Date] {
        let cal = calendar
        let allowed = Set(weekdays)
        var out: [Date] = []
        let anchorMonday = mondayContaining(anchor, cal: cal)
        var scan = cal.startOfDay(for: cal.date(byAdding: .day, value: -1, to: windowStart) ?? windowStart)
        let endScan = cal.date(byAdding: .day, value: 1, to: windowEnd) ?? windowEnd
        var iterations = 0
        while scan <= endScan && iterations < 4000 {
            iterations += 1
            defer { scan = cal.date(byAdding: .day, value: 1, to: scan) ?? scan }
            let wd = cal.component(.weekday, from: scan)
            guard allowed.contains(wd) else { continue }
            guard let combined = combine(day: scan, timeFrom: timeFromAnchor, cal: cal) else { continue }
            if combined < anchor { continue }
            if let u = until, combined > u { continue }
            let monCombined = mondayContaining(combined, cal: cal)
            let days = cal.dateComponents([.day], from: anchorMonday, to: monCombined).day ?? 0
            if days < 0 { continue }
            let weekIndex = days / 7
            if weekIndex % interval != 0 { continue }
            if combined >= windowStart && combined <= windowEnd {
                out.append(combined)
                if let c = count, out.count >= c { break }
            }
        }
        return out.sorted()
    }

    private static func mondayContaining(_ date: Date, cal: Calendar) -> Date {
        let start = cal.startOfDay(for: date)
        let wd = cal.component(.weekday, from: start)
        let daysBack = (wd + 5) % 7
        return cal.date(byAdding: .day, value: -daysBack, to: start) ?? start
    }

    private static func combine(day: Date, timeFrom: Date, cal: Calendar) -> Date? {
        let h = cal.component(.hour, from: timeFrom)
        let m = cal.component(.minute, from: timeFrom)
        let s = cal.component(.second, from: timeFrom)
        return cal.date(bySettingHour: h, minute: m, second: s, of: day)
    }

    private static func isExcluded(start: Date, allDay: Bool, excluded: Set<Date>) -> Bool {
        guard !excluded.isEmpty else { return false }
        let cal = Calendar.current
        for ex in excluded {
            if allDay {
                if cal.isDate(start, inSameDayAs: ex) { return true }
            } else {
                if abs(ex.timeIntervalSince(start)) < 0.5 { return true }
            }
        }
        return false
    }

    struct RRule {
        var freq: String = "WEEKLY"
        var interval: Int = 1
        var until: Date?
        var count: Int?
        /// Swift weekday 1…7 (1=Sunday); empty ⇒ caller uses legacy weekly step.
        var byWeekday: [Int] = []
    }

    private static func parseRRULE(_ raw: String) -> RRule {
        let value = raw.split(separator: ":", maxSplits: 1).last.map(String.init) ?? raw
        var r = RRule()
        for part in value.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let k = String(kv[0]).uppercased()
            let v = String(kv[1])
            switch k {
            case "FREQ": r.freq = v.uppercased()
            case "INTERVAL": r.interval = Int(v) ?? 1
            case "COUNT": r.count = Int(v)
            case "BYDAY":
                r.byWeekday = v.split(separator: ",").compactMap(parseBYDAYToken)
            case "UNTIL":
                if v.count == 8 {
                    let f = DateFormatter()
                    f.dateFormat = "yyyyMMdd"
                    f.timeZone = TimeZone(secondsFromGMT: 0)
                    f.locale = Locale(identifier: "en_US_POSIX")
                    r.until = f.date(from: v)
                } else {
                    let f = DateFormatter()
                    f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
                    f.timeZone = TimeZone(secondsFromGMT: 0)
                    f.locale = Locale(identifier: "en_US_POSIX")
                    var vv = v
                    if vv.hasSuffix("Z") { vv.removeLast() }
                    r.until = f.date(from: String(vv.prefix(15)))
                }
            default: break
            }
        }
        return r
    }

    /// `MO`, `TU`, `1MO`, … → Swift weekday (ordinal prefix ignored).
    private static func parseBYDAYToken(_ sub: Substring) -> Int? {
        var t = String(sub).trimmingCharacters(in: .whitespaces).uppercased()
        while let first = t.first, first.isNumber { t.removeFirst() }
        guard t.count >= 2 else { return nil }
        let letters = String(t.prefix(2))
        switch letters {
        case "SU": return 1
        case "MO": return 2
        case "TU": return 3
        case "WE": return 4
        case "TH": return 5
        case "FR": return 6
        case "SA": return 7
        default: return nil
        }
    }
}

private extension Date {
    func subtractingTimeInterval(_ t: TimeInterval) -> Date {
        addingTimeInterval(-t)
    }
}
