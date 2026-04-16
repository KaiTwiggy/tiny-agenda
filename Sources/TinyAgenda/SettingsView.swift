import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @ObservedObject private var sparkle = SparkleCoordinator.shared
    @State private var urlDraft: String = ""
    @State private var saveError: String?

    /// Persisted like other settings; `SMAppService` alone can look “lost” if Settings is reopened without `onAppear`.
    @AppStorage(LaunchAtLogin.userPreferenceKey) private var openAtLogin = false
    @State private var launchAtLoginReady = false
    @State private var launchAtLoginError: String?
    @State private var launchAtLoginHint: String?

    var body: some View {
        Form {
            Section("Updates") {
                LabeledContent("Current version") {
                    Text(appVersionDisplay)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button("Update version now") {
                    SparkleCoordinator.shared.checkForUpdates()
                }
                LabeledContent("Last checked for update") {
                    Text(lastUpdateCheckDisplay)
                        .foregroundStyle(.secondary)
                }
                Toggle(
                    "Turn off automatic update checks",
                    isOn: Binding(
                        get: { !sparkle.automaticallyChecksForUpdates },
                        set: { off in sparkle.setAutomaticallyChecksForUpdates(!off) }
                    )
                )
                .disabled(!SparkleCoordinator.isConfiguredForUpdates)
                if SparkleCoordinator.isConfiguredForUpdates {
                    Text("Uses the Sparkle feed URL in the app’s Info.plist. New versions are published via GitHub Releases (see scripts/sparkle-release.md).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("In-app updates are disabled until you set SUFeedURL and SUPublicEDKey for your fork (see scripts/sparkle-release.md), then rebuild TinyAgenda.app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Startup") {
                Toggle("Open at login", isOn: $openAtLogin)
                    .disabled(!launchAtLoginToggleEnabled)
                    .onChange(of: openAtLogin) { _ in
                        guard launchAtLoginReady else { return }
                        persistLaunchAtLogin()
                    }
                if !LaunchAtLogin.isSupported {
                    Text("Available when you run TinyAgenda from TinyAgenda.app (see scripts/build-app.sh).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let launchAtLoginHint {
                    Text(launchAtLoginHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text("Paste your Google Calendar secret iCal URL (Google Calendar: Settings → Integrate calendar → Secret address in iCal format). The URL is stored in the Keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Calendar feed") {
                TextField("https://…", text: $urlDraft, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Save") { saveURL() }
                    Button("Clear") {
                        urlDraft = ""
                        try? viewModel.saveFeedURLAndSync("")
                        saveError = nil
                    }
                }
                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Refresh") {
                Stepper(
                    value: $viewModel.refreshIntervalSeconds,
                    in: 60...600,
                    step: 30
                ) {
                    Text("Every \(Int(viewModel.refreshIntervalSeconds)) seconds")
                }
                .onChange(of: viewModel.refreshIntervalSeconds) { _ in
                    viewModel.startRefreshLoop()
                }
            }

            Section("Menu bar") {
                Stepper(
                    value: $viewModel.menuBarVisibilityLeadMinutes,
                    in: 0...24 * 60,
                    step: 5
                ) {
                    if viewModel.menuBarVisibilityLeadMinutes == 0 {
                        Text("Show next meeting: always")
                    } else {
                        Text("Show next meeting: \(viewModel.menuBarVisibilityLeadMinutes) min before start")
                    }
                }
                Text("When not zero, the menu bar shows the upcoming meeting only within this many minutes of its start; otherwise it shows “TinyAgenda”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Picker("When no meeting is shown in the bar", selection: $viewModel.menuBarIdleShowsText) {
                    Text("Icon and text (TinyAgenda / No meetings)")
                        .tag(true)
                    Text("Icon only")
                        .tag(false)
                }
                .pickerStyle(.inline)
                Text("Meeting countdowns (e.g. “in 5m · …”) always include text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Stepper(
                    value: $viewModel.menuBarFadeOutMinutes,
                    in: 0...24 * 60,
                    step: 5
                ) {
                    if viewModel.menuBarFadeOutMinutes == 0 {
                        Text("Hide “Now · …” after start: never (until event ends)")
                    } else {
                        Text("Hide “Now · …” \(viewModel.menuBarFadeOutMinutes) min after start")
                    }
                }
                Text("After this time from the event’s start, the menu bar moves on to the next meeting or idle text. Set to zero to keep showing during the whole event.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Events") {
                Toggle(
                    "Skip tentative events",
                    isOn: $viewModel.omitTentativeEvents
                )
                Text("Hides events whose feed marks them tentative (`STATUS:TENTATIVE` or an attendee responded with tentative).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(
                    "Skip events you haven’t responded to",
                    isOn: $viewModel.omitNeedsActionEvents
                )
                Text("Hides events where any attendee line has `PARTSTAT=NEEDS-ACTION` (common for unanswered invitations).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if viewModel.hiddenEventIds.isEmpty {
                    Text("Hidden events: none (use Hide on an event in the menu bar list).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack {
                        Text("Hidden events: \(viewModel.hiddenEventIds.count)")
                        Spacer()
                        Button("Restore all hidden") {
                            viewModel.clearHiddenEvents()
                        }
                    }
                }
            }

            Section("Reminders") {
                if !NotificationManager.isAvailable {
                    Text("Banner notifications only work when the app is run from TinyAgenda.app (use scripts/build-app.sh, then open the .app). Running with swift run disables notifications but the menu bar still works.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Banner notifications (toast)", isOn: $viewModel.toastNotificationsEnabled)
                Text("When off, no reminders are scheduled; the menu bar is unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Notify this many minutes before each event starts:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach([5, 10, 15, 30, 60], id: \.self) { m in
                    Toggle("\(m) minutes", isOn: binding(for: m))
                }
            }

            Section("Quiet hours") {
                Toggle("Suppress notifications during quiet hours", isOn: $viewModel.quietHoursEnabled)
                Stepper("Start hour: \(viewModel.quietStartHour):00", value: $viewModel.quietStartHour, in: 0...23)
                Stepper("End hour: \(viewModel.quietEndHour):00", value: $viewModel.quietEndHour, in: 0...23)
                Text("Overnight ranges are supported (e.g. 22:00–07:00).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 480)
        .onAppear {
            launchAtLoginReady = false
            urlDraft = viewModel.feedURLString
            sparkle.refreshUpdateMetadata()
            refreshLaunchAtLoginState()
            launchAtLoginReady = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLaunchAtLoginState()
            sparkle.refreshUpdateMetadata()
        }
    }

    private var appVersionDisplay: String {
        let short =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let build, !build.isEmpty {
            return "\(short) (\(build))"
        }
        return short
    }

    private var lastUpdateCheckDisplay: String {
        guard SparkleCoordinator.isConfiguredForUpdates else {
            return "—"
        }
        guard let date = sparkle.lastUpdateCheckDate else {
            return "Never"
        }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    private var launchAtLoginToggleEnabled: Bool {
        if #available(macOS 13.0, *) {
            return LaunchAtLogin.isSupported
        }
        return false
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginError = nil
        guard #available(macOS 13.0, *) else {
            launchAtLoginHint = nil
            return
        }
        guard LaunchAtLogin.isSupported else {
            launchAtLoginHint = nil
            return
        }
        launchAtLoginHint = LaunchAtLogin.statusHint
    }

    private func persistLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        launchAtLoginError = nil
        do {
            try LaunchAtLogin.setEnabled(openAtLogin)
            launchAtLoginHint = LaunchAtLogin.statusHint
        } catch {
            launchAtLoginError = error.localizedDescription
            openAtLogin = LaunchAtLogin.isRegistered
        }
    }

    private func binding(for minute: Int) -> Binding<Bool> {
        Binding(
            get: { viewModel.leadMinutes.contains(minute) },
            set: { on in
                var s = Set(viewModel.leadMinutes)
                if on { s.insert(minute) } else { s.remove(minute) }
                viewModel.leadMinutes = s.sorted()
            }
        )
    }

    private func saveURL() {
        saveError = nil
        do {
            try viewModel.saveFeedURLAndSync(urlDraft)
        } catch {
            saveError = error.localizedDescription
        }
    }
}
