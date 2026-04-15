import Foundation

public struct CalendarEvent: Identifiable, Equatable, Hashable {
    public let id: String
    public let uid: String
    public let start: Date
    public let end: Date
    public let title: String
    public let description: String
    public let location: String
    public let isAllDay: Bool
    /// `STATUS:TENTATIVE` on the VEVENT.
    public let isStatusTentative: Bool
    /// Any `ATTENDEE` line includes `PARTSTAT=NEEDS-ACTION`.
    public let hasNeedsActionAttendee: Bool
    /// Any `ATTENDEE` line includes `PARTSTAT=TENTATIVE` (responded “maybe”).
    public let hasTentativeAttendee: Bool

    public init(
        id: String,
        uid: String,
        start: Date,
        end: Date,
        title: String,
        description: String,
        location: String,
        isAllDay: Bool,
        isStatusTentative: Bool,
        hasNeedsActionAttendee: Bool,
        hasTentativeAttendee: Bool
    ) {
        self.id = id
        self.uid = uid
        self.start = start
        self.end = end
        self.title = title
        self.description = description
        self.location = location
        self.isAllDay = isAllDay
        self.isStatusTentative = isStatusTentative
        self.hasNeedsActionAttendee = hasNeedsActionAttendee
        self.hasTentativeAttendee = hasTentativeAttendee
    }

    public var joinURL: URL? {
        JoinURLExtractor.firstJoinURL(
            in: [title, description, location].joined(separator: "\n")
        )
    }

    public var shortTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "(No title)" : t
    }
}

public enum JoinURLExtractor {
    private static let urlRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s<>\"'\)\]]+"#,
        options: []
    )

    public static func firstJoinURL(in text: String) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = urlRegex.firstMatch(in: text, options: [], range: range),
              let r = Range(m.range, in: text)
        else { return nil }
        var s = String(text[r])
        while let last = s.last, ".,".contains(last) { s.removeLast() }
        return URL(string: s)
    }
}
