import Foundation
import Security

/// Minimal Keychain wrapper for storing Alpaca API credentials on-device.
enum KeychainStore {
    private static let service = "com.chailfin.cmfsignaltrader"

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Keys used to persist credentials in the Keychain (mirrors the `.env` names in cmf_spy.py / cmf_trader.py).
enum CredentialKey {
    static let dataKey = "apiDataKey"
    static let dataSecret = "apiDataSecret"
    static let tradeKey = "apiTradeKey"
    static let tradeSecret = "apiTradeSecret"
}
