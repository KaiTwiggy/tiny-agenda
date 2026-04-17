import Foundation
import Security

/// Stores the user's calendar feed URL in the macOS login Keychain.
///
/// The public API (`saveFeedURL`, `loadFeedURL`, `deleteFeedURL`) hides the Keychain service
/// name and does the silent migration from the legacy pre-rebrand service. The parameterised
/// overloads are exposed so tests can round-trip under a unique service name without touching
/// the real application slot.
public enum KeychainHelper {
    /// Current bundle Keychain service identifier (matches `CFBundleIdentifier`).
    public static let service = "com.tinyagenda.ics"
    /// Pre-rebrand service; still consulted by `loadFeedURL()` so upgrades keep the saved URL.
    public static let legacyService = "com.calendarreminder.ics"
    /// Generic-password account slot; stable across services.
    public static let account = "secretFeedURL"

    // MARK: - High-level API used by the app

    public static func saveFeedURL(_ urlString: String) throws {
        try saveFeedURL(urlString, service: service, account: account)
    }

    public static func loadFeedURL() -> String? {
        if let s = loadFeedURL(service: service, account: account) { return s }
        // Opportunistically migrate from the pre-rebrand service so the legacy entry
        // doesn't linger in the user's Keychain for years after the rename. Best-effort:
        // failures to copy forward or to delete don't break `loadFeedURL` for the caller.
        if let legacy = loadFeedURL(service: legacyService, account: account) {
            try? saveFeedURL(legacy, service: service, account: account)
            deleteFeedURL(service: legacyService, account: account)
            return legacy
        }
        return nil
    }

    public static func deleteFeedURL() {
        for svc in [service, legacyService] {
            deleteFeedURL(service: svc, account: account)
        }
    }

    // MARK: - Parameterised helpers (public for tests + migration path)

    public static func saveFeedURL(_ urlString: String, service: String, account: String) throws {
        let data = Data(urlString.utf8)
        deleteFeedURL(service: service, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.operationFailed(status)
        }
    }

    public static func loadFeedURL(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data,
              let s = String(data: data, encoding: .utf8), !s.isEmpty
        else { return nil }
        return s
    }

    public static func deleteFeedURL(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    public enum KeychainError: Error {
        case operationFailed(OSStatus)
    }
}
