import AppKit
import Combine
import Foundation
import OSLog
import Sparkle

/// Owns Sparkle’s `SPUStandardUpdaterController` and exposes “Check for Updates…”.
@MainActor
final class SparkleCoordinator: NSObject, ObservableObject {
    static let shared = SparkleCoordinator()

    /// Unified-logging channel for Sparkle-adjacent events. Filter in Console.app with
    /// `subsystem:tools.tinyagenda.TinyAgenda category:Sparkle`.
    private static let log = Logger(subsystem: "tools.tinyagenda.TinyAgenda", category: "Sparkle")

    /// Mirrored from Sparkle (`SULastCheckTime` / `lastUpdateCheckDate`).
    @Published private(set) var lastUpdateCheckDate: Date? = UserDefaults.standard.object(forKey: SparkleDefaults.lastCheckTime) as? Date
    /// Mirrored from `SPUUpdater.automaticallyChecksForUpdates` (`SUEnableAutomaticChecks`).
    @Published private(set) var automaticallyChecksForUpdates: Bool = SparkleCoordinator.readAutomaticChecksFromDefaults()

    private var controller: SPUStandardUpdaterController?

    private static func readAutomaticChecksFromDefaults() -> Bool {
        if UserDefaults.standard.object(forKey: SparkleDefaults.enableAutomaticChecks) != nil {
            return UserDefaults.standard.bool(forKey: SparkleDefaults.enableAutomaticChecks)
        }
        if let plist = Bundle.main.object(forInfoDictionaryKey: SparkleDefaults.enableAutomaticChecks) as? Bool {
            return plist
        }
        return true
    }

    /// `true` when `SUPublicEDKey` / `SUFeedURL` are set for your distribution (see README).
    static var isConfiguredForUpdates: Bool {
        guard let pk = Bundle.main.object(forInfoDictionaryKey: SparkleDefaults.publicEDKey) as? String else {
            return false
        }
        let trimmed = pk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.localizedCaseInsensitiveContains("REPLACE") else {
            return false
        }
        guard let feed = Bundle.main.object(forInfoDictionaryKey: SparkleDefaults.feedURL) as? String else {
            return false
        }
        let f = feed.trimmingCharacters(in: .whitespacesAndNewlines)
        return !f.isEmpty
            && !f.localizedCaseInsensitiveContains("YOUR_GITHUB")
            && !f.contains("OWNER/REPO")
    }

    /// Starts automatic update checks when Sparkle keys and feed URL are configured.
    func start() {
        guard controller == nil else {
            syncPublishedFromUpdater()
            return
        }
        guard Self.isConfiguredForUpdates else {
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        syncPublishedFromUpdater()
    }

    /// Call when opening Settings so version metadata matches Sparkle’s updater.
    func refreshUpdateMetadata() {
        start()
        syncPublishedFromUpdater()
    }

    func setAutomaticallyChecksForUpdates(_ value: Bool) {
        start()
        controller?.updater.automaticallyChecksForUpdates = value
        automaticallyChecksForUpdates = controller?.updater.automaticallyChecksForUpdates ?? value
    }

    private func syncPublishedFromUpdater() {
        guard let updater = controller?.updater else {
            lastUpdateCheckDate = UserDefaults.standard.object(forKey: SparkleDefaults.lastCheckTime) as? Date
            automaticallyChecksForUpdates = Self.readAutomaticChecksFromDefaults()
            return
        }
        lastUpdateCheckDate = updater.lastUpdateCheckDate
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        guard Self.isConfiguredForUpdates else {
            let alert = NSAlert()
            alert.messageText = "Updates not configured"
            alert.informativeText =
                "Set SUFeedURL and SUPublicEDKey in the app Info.plist (see README and scripts/sparkle-release.md), rebuild TinyAgenda.app, then try again."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        start()
        controller?.checkForUpdates(nil)
    }

    private var isPlaceholderFeedURL: Bool {
        guard let url = Bundle.main.object(forInfoDictionaryKey: SparkleDefaults.feedURL) as? String else {
            return true
        }
        return url.contains("YOUR_GITHUB") || url.contains("OWNER/REPO")
    }
}

// `SPUUpdaterDelegate` is not MainActor-isolated; Sparkle may call these from its own queues.
extension SparkleCoordinator: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFailToLoadAppcastWithError error: Error) {
        Task { @MainActor in
            if self.isPlaceholderFeedURL {
                return
            }
            let ns = error as NSError
            // Avoid logging `userInfo` directly: it may echo the full appcast URL. `privacy: .public`
            // on the domain/code is safe (no PII); everything else is Logger's default (private).
            Self.log.error(
                "Failed to load appcast: \(ns.localizedDescription, privacy: .public) (domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public))"
            )
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        Task { @MainActor in
            self.lastUpdateCheckDate = updater.lastUpdateCheckDate
        }
    }
}
