import TinyAgendaCore
import Foundation
import XCTest

/// Exercises the real Keychain under throwaway service names so we never touch the user's
/// real TinyAgenda feed URL. Each test picks a UUID-based service and deletes it afterwards.
/// If the host denies Keychain writes (e.g. some sandboxed CI runners) the test is skipped
/// rather than failing, since the behavior we're checking is host-level, not logical.
final class KeychainHelperTests: XCTestCase {
    private var service: String = ""
    private var legacyService: String = ""
    private let account = "secretFeedURL-test"

    override func setUp() {
        super.setUp()
        let uuid = UUID().uuidString
        service = "tools.tinyagenda.tests.current.\(uuid)"
        legacyService = "tools.tinyagenda.tests.legacy.\(uuid)"
    }

    override func tearDown() {
        KeychainHelper.deleteFeedURL(service: service, account: account)
        KeychainHelper.deleteFeedURL(service: legacyService, account: account)
        super.tearDown()
    }

    private func requireKeychainWriteable() throws {
        do {
            try KeychainHelper.saveFeedURL(
                "https://example.invalid/probe",
                service: service,
                account: account
            )
        } catch {
            throw XCTSkip("Keychain not writable in this environment: \(error)")
        }
        KeychainHelper.deleteFeedURL(service: service, account: account)
    }

    func testSaveLoadDeleteRoundTrip() throws {
        try requireKeychainWriteable()
        let url = "https://calendar.example/feed.ics?token=abc123"

        try KeychainHelper.saveFeedURL(url, service: service, account: account)
        XCTAssertEqual(
            KeychainHelper.loadFeedURL(service: service, account: account),
            url
        )

        KeychainHelper.deleteFeedURL(service: service, account: account)
        XCTAssertNil(KeychainHelper.loadFeedURL(service: service, account: account))
    }

    func testSaveOverwritesPreviousValue() throws {
        try requireKeychainWriteable()
        try KeychainHelper.saveFeedURL("https://first.example/a", service: service, account: account)
        try KeychainHelper.saveFeedURL("https://second.example/b", service: service, account: account)
        XCTAssertEqual(
            KeychainHelper.loadFeedURL(service: service, account: account),
            "https://second.example/b"
        )
    }

    func testLoadReturnsNilWhenMissing() {
        XCTAssertNil(KeychainHelper.loadFeedURL(service: service, account: account))
    }

    /// Verifies the parameterised helpers the migration path relies on: writing under a
    /// "legacy" service and reading back via the same parameters must round-trip.
    /// (The top-level `KeychainHelper.loadFeedURL()` auto-migrates, but testing that would
    /// clobber the user's real entry, so we only exercise the building blocks here.)
    func testParameterisedHelpersAreIsolatedByService() throws {
        try requireKeychainWriteable()
        try KeychainHelper.saveFeedURL("https://legacy.example/x", service: legacyService, account: account)
        try KeychainHelper.saveFeedURL("https://current.example/y", service: service, account: account)

        XCTAssertEqual(
            KeychainHelper.loadFeedURL(service: legacyService, account: account),
            "https://legacy.example/x"
        )
        XCTAssertEqual(
            KeychainHelper.loadFeedURL(service: service, account: account),
            "https://current.example/y"
        )

        KeychainHelper.deleteFeedURL(service: legacyService, account: account)
        XCTAssertNil(KeychainHelper.loadFeedURL(service: legacyService, account: account))
        XCTAssertEqual(
            KeychainHelper.loadFeedURL(service: service, account: account),
            "https://current.example/y",
            "deleting the legacy entry must not affect the current one"
        )
    }
}
