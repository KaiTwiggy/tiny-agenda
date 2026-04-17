import AppKit
import TinyAgendaCore
import Combine
import Foundation
import OSLog
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

    /// Unified logger for feed fetch/parse failures. Console.app filter:
    /// `subsystem:tools.tinyagenda.TinyAgenda category:Feed`. Unified logging coalesces
    /// repeated identical messages, so a persistently-broken feed doesn't spam the log.
    private static let feedLog = Logger(subsystem: "tools.tinyagenda.TinyAgenda", category: "Feed")

    /// Background refresh loop. Restarted (and cancelled) whenever the interval changes.
    private var refreshLoopTask: Task<Void, Never>?
    /// In-flight `refresh()` call. Cancelled by callers that kick a new refresh before the
    /// previous one finished (e.g. user edits the feed URL and we want the old fetch to bail
    /// out rather than overwriting fresh state on completion).
    private var currentRefreshTask: Task<Void, Never>?
    private var menuBarTickCancellable: AnyCancellable?
    /// How many consecutive fetch failures we've seen; drives exponential backoff in the loop.
    private var consecutiveFailures = 0

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
        scheduleRefresh()
    }

    deinit {
        refreshLoopTask?.cancel()
        currentRefreshTask?.cancel()
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
            lastError = nil
            consecutiveFailures = 0
            updateMenuBarTitle()
            currentRefreshTask?.cancel()
            Task { await NotificationManager.shared.cancelAllPending() }
            return
        }
        try KeychainHelper.saveFeedURL(trimmed)
        feedURLString = trimmed
        consecutiveFailures = 0
        scheduleRefresh()
    }

    /// Kick off a refresh, cancelling any in-flight one so its result can't overwrite the
    /// new request. Replacement for the old `refreshGeneration` counter.
    func scheduleRefresh() {
        currentRefreshTask?.cancel()
        let task = Task<Void, Never> { [weak self] in
            await self?.refresh()
        }
        currentRefreshTask = task
    }

    func startRefreshLoop() {
        refreshLoopTask?.cancel()
        refreshLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delaySeconds = self.nextRefreshDelaySeconds()
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                if Task.isCancelled { return }
                // Drive the loop through the same scheduler so external refreshes still cancel
                // the loop's in-flight fetch instead of racing it.
                await self.runScheduledRefresh()
            }
        }
    }

    /// Runs a refresh and awaits its completion, going through `currentRefreshTask` so other
    /// callers can cancel it while it's running.
    private func runScheduledRefresh() async {
        currentRefreshTask?.cancel()
        let task = Task<Void, Never> { [weak self] in
            await self?.refresh()
        }
        currentRefreshTask = task
        await task.value
    }

    /// Delay before the next loop iteration. Success → refreshIntervalSeconds. Failure →
    /// exponential backoff (`interval * 2^failures`) capped at one hour, plus up to ±25%
    /// jitter so a flaky feed doesn't retry in lockstep every cycle.
    private func nextRefreshDelaySeconds() -> Double {
        let base = refreshIntervalSeconds > 15 ? refreshIntervalSeconds : 120
        guard consecutiveFailures > 0 else { return base }
        let maxBackoff: Double = 3600
        let exponent = min(consecutiveFailures, 6)
        let scale = pow(2.0, Double(exponent))
        let jitter = Double.random(in: -0.25...0.25) * base
        return min(maxBackoff, max(base, base * scale + jitter))
    }

    func refresh() async {
        guard !feedURLString.isEmpty else {
            events = []
            lastSuccessfulRefresh = nil
            lastError = nil
            consecutiveFailures = 0
            updateMenuBarTitle()
            await NotificationManager.shared.cancelAllPending()
            return
        }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        if Task.isCancelled { return }
        let urlString = feedURLString
        do {
            let ics = try await ICSFetcher.fetchString(from: urlString)
            if Task.isCancelled { return }
            let parsed = ICSParser.parse(ics)
            let now = Date()
            events = parsed.filter { $0.end > now }.sorted { $0.start < $1.start }
            let currentIds = Set(events.map(\.id))
            hiddenEventIds = hiddenEventIds.intersection(currentIds)
            lastSuccessfulRefresh = Date()
            consecutiveFailures = 0
            updateMenuBarTitle()
            if Task.isCancelled { return }
            await NotificationManager.shared.rescheduleNotifications(
                events: upcomingVisibleEvents(now: now),
                leadMinutes: leadMinutes,
                quietHoursEnabled: quietHoursEnabled,
                quietStartHour: quietStartHour,
                quietEndHour: quietEndHour,
                toastNotificationsEnabled: toastNotificationsEnabled
            )
        } catch is CancellationError {
            return
        } catch {
            if Task.isCancelled { return }
            consecutiveFailures += 1
            lastError = error.localizedDescription
            // `localizedDescription` is redacted in `ICSFetcher.FetchError` (covered by tests),
            // so it's safe to mark `.public`. Failure count helps spot flaky-feed trends in Console.
            Self.feedLog.error(
                "Refresh failed (attempt #\(self.consecutiveFailures, privacy: .public)): \(error.localizedDescription, privacy: .public)"
            )
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
