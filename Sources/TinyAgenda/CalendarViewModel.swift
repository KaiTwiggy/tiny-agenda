import AppKit
import TinyAgendaCore
import Combine
import Foundation
import UserNotifications

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var feedURLString: String
    @Published var events: [CalendarEvent] = []
    @Published var lastError: String?
    /// Set when a feed fetch completed successfully; cleared when the feed URL is empty.
    @Published var lastSuccessfulRefresh: Date?
    @Published var isRefreshing = false
    @Published var menuBarTitle: String = "TinyAgenda"

    @Published var refreshIntervalSeconds: Double {
        didSet { UserDefaults.standard.set(refreshIntervalSeconds, forKey: Keys.refreshInterval) }
    }

    @Published var leadMinutes: [Int] {
        didSet {
            UserDefaults.standard.set(leadMinutes, forKey: Keys.leadMinutes)
            Task { await rescheduleNotificationsOnly() }
        }
    }

    @Published var quietHoursEnabled: Bool {
        didSet {
            UserDefaults.standard.set(quietHoursEnabled, forKey: Keys.quietHoursEnabled)
            Task { await rescheduleNotificationsOnly() }
        }
    }

    @Published var quietStartHour: Int {
        didSet {
            UserDefaults.standard.set(quietStartHour, forKey: Keys.quietStartHour)
            Task { await rescheduleNotificationsOnly() }
        }
    }

    @Published var quietEndHour: Int {
        didSet {
            UserDefaults.standard.set(quietEndHour, forKey: Keys.quietEndHour)
            Task { await rescheduleNotificationsOnly() }
        }
    }

    /// Minutes before an event’s start when it becomes visible in the menu bar. `0` means always show the next event (no lead-time limit).
    @Published var menuBarVisibilityLeadMinutes: Int {
        didSet {
            UserDefaults.standard.set(menuBarVisibilityLeadMinutes, forKey: Keys.menuBarVisibilityLeadMinutes)
            updateMenuBarTitle()
        }
    }

    /// When `true`, idle labels “TinyAgenda” or “No meetings” appear next to the icon; when `false`, only the icon is shown in those states (meeting countdowns still show text).
    @Published var menuBarIdleShowsText: Bool {
        didSet {
            UserDefaults.standard.set(menuBarIdleShowsText, forKey: Keys.menuBarIdleShowsText)
        }
    }

    /// Minutes after an event’s start during which the menu bar still shows “Now · …”. `0` means keep showing until the event ends (no fade).
    @Published var menuBarFadeOutMinutes: Int {
        didSet {
            UserDefaults.standard.set(menuBarFadeOutMinutes, forKey: Keys.menuBarFadeOutMinutes)
            updateMenuBarTitle()
        }
    }

    /// When `false`, no banner/toast notifications are scheduled (menu bar is unchanged).
    @Published var toastNotificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(toastNotificationsEnabled, forKey: Keys.toastNotificationsEnabled)
            Task { await rescheduleNotificationsOnly() }
        }
    }

    /// Hidden by the user (menu); persisted by event `id` until the instance disappears from the feed.
    @Published var hiddenEventIds: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(hiddenEventIds), forKey: Keys.hiddenEventIds)
            updateMenuBarTitle()
        }
    }

    @Published var omitTentativeEvents: Bool {
        didSet {
            UserDefaults.standard.set(omitTentativeEvents, forKey: Keys.omitTentativeEvents)
            updateMenuBarTitle()
            Task { await rescheduleNotificationsOnly() }
        }
    }

    @Published var omitNeedsActionEvents: Bool {
        didSet {
            UserDefaults.standard.set(omitNeedsActionEvents, forKey: Keys.omitNeedsActionEvents)
            updateMenuBarTitle()
            Task { await rescheduleNotificationsOnly() }
        }
    }

    /// Local alias so existing call sites (`Keys.refreshInterval`) keep working; canonical
    /// key list lives in `Defaults.swift`.
    private typealias Keys = Defaults.Calendar

    private var refreshTask: Task<Void, Never>?
    private var menuBarTickCancellable: AnyCancellable?
    /// Only the latest `refresh()` may publish results (manual refresh vs timer).
    private var refreshGeneration = 0

    init() {
        feedURLString = KeychainHelper.loadFeedURL() ?? ""
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.refreshInterval) == nil {
            defaults.set(120.0, forKey: Keys.refreshInterval)
        }
        refreshIntervalSeconds = defaults.double(forKey: Keys.refreshInterval)
        leadMinutes = (defaults.array(forKey: Keys.leadMinutes) as? [Int]) ?? [5, 10, 15]
        quietHoursEnabled = defaults.bool(forKey: Keys.quietHoursEnabled)
        if defaults.object(forKey: Keys.quietStartHour) == nil {
            defaults.set(22, forKey: Keys.quietStartHour)
        }
        if defaults.object(forKey: Keys.quietEndHour) == nil {
            defaults.set(7, forKey: Keys.quietEndHour)
        }
        quietStartHour = defaults.integer(forKey: Keys.quietStartHour)
        quietEndHour = defaults.integer(forKey: Keys.quietEndHour)
        if defaults.object(forKey: Keys.menuBarVisibilityLeadMinutes) == nil {
            defaults.set(0, forKey: Keys.menuBarVisibilityLeadMinutes)
        }
        menuBarVisibilityLeadMinutes = defaults.integer(forKey: Keys.menuBarVisibilityLeadMinutes)
        if defaults.object(forKey: Keys.menuBarIdleShowsText) == nil {
            defaults.set(true, forKey: Keys.menuBarIdleShowsText)
        }
        menuBarIdleShowsText = defaults.bool(forKey: Keys.menuBarIdleShowsText)
        if defaults.object(forKey: Keys.menuBarFadeOutMinutes) == nil {
            defaults.set(0, forKey: Keys.menuBarFadeOutMinutes)
        }
        menuBarFadeOutMinutes = defaults.integer(forKey: Keys.menuBarFadeOutMinutes)
        if defaults.object(forKey: Keys.toastNotificationsEnabled) == nil {
            defaults.set(true, forKey: Keys.toastNotificationsEnabled)
        }
        toastNotificationsEnabled = defaults.bool(forKey: Keys.toastNotificationsEnabled)
        hiddenEventIds = Set(defaults.stringArray(forKey: Keys.hiddenEventIds) ?? [])
        if defaults.object(forKey: Keys.omitTentativeEvents) == nil {
            defaults.set(false, forKey: Keys.omitTentativeEvents)
        }
        if defaults.object(forKey: Keys.omitNeedsActionEvents) == nil {
            defaults.set(false, forKey: Keys.omitNeedsActionEvents)
        }
        omitTentativeEvents = defaults.bool(forKey: Keys.omitTentativeEvents)
        omitNeedsActionEvents = defaults.bool(forKey: Keys.omitNeedsActionEvents)

        NotificationManager.shared.requestAuthorizationIfNeeded()
        startRefreshLoop()
        startMenuBarTick()
        Task { await refresh() }
    }

    /// Periodically refresh the menu bar title so countdowns and fade-out update without waiting for the feed refresh.
    private func startMenuBarTick() {
        menuBarTickCancellable?.cancel()
        menuBarTickCancellable = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateMenuBarTitle()
            }
    }

    func saveFeedURLAndSync(_ urlString: String) throws {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainHelper.deleteFeedURL()
            feedURLString = ""
            events = []
            hiddenEventIds = []
            lastSuccessfulRefresh = nil
            updateMenuBarTitle()
            Task { await NotificationManager.shared.cancelAllPending() }
            return
        }
        try KeychainHelper.saveFeedURL(trimmed)
        feedURLString = trimmed
        Task { await refresh() }
    }

    func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let sec = await MainActor.run {
                    let v = self.refreshIntervalSeconds
                    return v > 15 ? v : 120
                }
                try? await Task.sleep(nanoseconds: UInt64(sec * 1_000_000_000))
                await self.refresh()
            }
        }
    }

    func refresh() async {
        refreshGeneration += 1
        let gen = refreshGeneration
        guard !feedURLString.isEmpty else {
            events = []
            lastSuccessfulRefresh = nil
            updateMenuBarTitle()
            await NotificationManager.shared.cancelAllPending()
            return
        }
        isRefreshing = true
        lastError = nil
        defer {
            if gen == refreshGeneration {
                isRefreshing = false
            }
        }
        do {
            let ics = try await ICSFetcher.fetchString(from: feedURLString)
            let parsed = ICSParser.parse(ics)
            let now = Date()
            guard gen == refreshGeneration else { return }
            events = parsed.filter { $0.end > now }.sorted { $0.start < $1.start }
            let currentIds = Set(events.map(\.id))
            hiddenEventIds = hiddenEventIds.intersection(currentIds)
            lastSuccessfulRefresh = Date()
            updateMenuBarTitle()
            await NotificationManager.shared.rescheduleNotifications(
                events: upcomingVisibleEvents(now: now),
                leadMinutes: leadMinutes,
                quietHoursEnabled: quietHoursEnabled,
                quietStartHour: quietStartHour,
                quietEndHour: quietEndHour,
                toastNotificationsEnabled: toastNotificationsEnabled
            )
        } catch {
            guard gen == refreshGeneration else { return }
            lastError = error.localizedDescription
        }
    }

    private func rescheduleNotificationsOnly() async {
        await NotificationManager.shared.rescheduleNotifications(
            events: upcomingVisibleEvents(),
            leadMinutes: leadMinutes,
            quietHoursEnabled: quietHoursEnabled,
            quietStartHour: quietStartHour,
            quietEndHour: quietEndHour,
            toastNotificationsEnabled: toastNotificationsEnabled
        )
    }

    /// Upcoming instances after omit filters and hidden IDs (menu bar, list, notifications).
    func upcomingVisibleEvents(now: Date = Date()) -> [CalendarEvent] {
        events
            .filter { $0.end > now }
            .filter { !hiddenEventIds.contains($0.id) }
            .filter { e in
                if omitTentativeEvents, e.isStatusTentative || e.hasTentativeAttendee {
                    return false
                }
                if omitNeedsActionEvents, e.hasNeedsActionAttendee {
                    return false
                }
                return true
            }
            .sorted { $0.start < $1.start }
    }

    func hideEvent(id: String) {
        hiddenEventIds = hiddenEventIds.union([id])
        Task { await rescheduleNotificationsOnly() }
    }

    func unhideEvent(id: String) {
        hiddenEventIds = hiddenEventIds.subtracting([id])
        Task { await rescheduleNotificationsOnly() }
    }

    func clearHiddenEvents() {
        hiddenEventIds = []
        Task { await rescheduleNotificationsOnly() }
    }

    /// String for `NSStatusItem`’s title: may be empty when idle and `menuBarIdleShowsText` is off.
    var menuBarStatusItemTitle: String {
        let raw = menuBarTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = raw.isEmpty ? "TinyAgenda" : raw
        if menuBarIdleShowsText { return display }
        if display == "TinyAgenda" || display == "No meetings" {
            return ""
        }
        return display
    }

    func updateMenuBarTitle() {
        let now = Date()
        let upcoming = upcomingVisibleEvents(now: now)
            .filter { !$0.isAllDay }

        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"

        for next in upcoming {
            if now < next.start {
                if menuBarVisibilityLeadMinutes > 0 {
                    let secondsUntilStart = next.start.timeIntervalSince(now)
                    if secondsUntilStart > Double(menuBarVisibilityLeadMinutes * 60) {
                        menuBarTitle = "TinyAgenda"
                        return
                    }
                }
                let timeStr = tf.string(from: next.start)
                let title = next.shortTitle
                let maxLen = 26
                let truncated =
                    title.count > maxLen ? String(title.prefix(maxLen - 1)) + "…" : title
                let mins = Int(ceil(next.start.timeIntervalSince(now) / 60))
                if mins <= 0 {
                    menuBarTitle = "Now · \(truncated)"
                } else if mins < 60 {
                    menuBarTitle = "in \(mins)m · \(truncated)"
                } else {
                    menuBarTitle = "\(timeStr) \(truncated)"
                }
                return
            }
            if next.start <= now, now < next.end {
                if menuBarFadeOutMinutes > 0 {
                    let fadeEnd = next.start.addingTimeInterval(Double(menuBarFadeOutMinutes * 60))
                    if now >= fadeEnd {
                        continue
                    }
                }
                let title = next.shortTitle
                let maxLen = 26
                let truncated =
                    title.count > maxLen ? String(title.prefix(maxLen - 1)) + "…" : title
                menuBarTitle = "Now · \(truncated)"
                return
            }
        }

        menuBarTitle = "No meetings"
    }
}
