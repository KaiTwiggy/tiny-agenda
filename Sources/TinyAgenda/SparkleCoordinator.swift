import AppKit
import Foundation
import Sparkle

/// Owns Sparkle’s `SPUStandardUpdaterController` and exposes “Check for Updates…”.
@MainActor
final class SparkleCoordinator: NSObject, SPUUpdaterDelegate {
    static let shared = SparkleCoordinator()

    private var controller: SPUStandardUpdaterController?

    /// `true` when `SUPublicEDKey` / `SUFeedURL` are set for your distribution (see README).
    static var isConfiguredForUpdates: Bool {
        guard let pk = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        let trimmed = pk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.localizedCaseInsensitiveContains("REPLACE") else {
            return false
        }
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else {
            return false
        }
        let f = feed.trimmingCharacters(in: .whitespacesAndNewlines)
        return !f.isEmpty
            && !f.localizedCaseInsensitiveContains("YOUR_GITHUB")
            && !f.contains("OWNER/REPO")
    }

    /// Starts automatic update checks when Sparkle keys and feed URL are configured.
    func start() {
        guard controller == nil else { return }
        guard Self.isConfiguredForUpdates else {
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
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

    func updater(_ updater: SPUUpdater, didFailToLoadAppcastWithError error: Error) {
        if _isPlaceholderFeedURL {
            return
        }
        NSLog("TinyAgenda Sparkle: failed to load appcast: \(error.localizedDescription)")
    }

    private var _isPlaceholderFeedURL: Bool {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else {
            return true
        }
        return url.contains("YOUR_GITHUB") || url.contains("OWNER/REPO")
    }
}
