import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.tinyagenda.ics"
    /// Previous bundle keychain service; still read so upgrades keep the saved feed URL.
    private static let legacyService = "com.calendarreminder.ics"
    private static let account = "secretFeedURL"

    static func saveFeedURL(_ urlString: String) throws {
        let data = Data(urlString.utf8)
        deleteFeedURL()
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

    static func loadFeedURL() -> String? {
        if let s = loadFeedURL(service: service) { return s }
        // Opportunistically migrate from the pre-rebrand service so the legacy entry
        // doesn't linger in the user's Keychain for years after the rename. Best-effort:
        // failures to copy forward or to delete don't break `loadFeedURL` for the caller.
        if let legacy = loadFeedURL(service: legacyService) {
            try? saveFeedURL(legacy)
            deleteFeedURL(service: legacyService)
            return legacy
        }
        return nil
    }

    private static func loadFeedURL(service: String) -> String? {
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

    private static func deleteFeedURL(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteFeedURL() {
        for svc in [service, legacyService] {
            deleteFeedURL(service: svc)
        }
    }

    enum KeychainError: Error {
        case operationFailed(OSStatus)
    }
}
