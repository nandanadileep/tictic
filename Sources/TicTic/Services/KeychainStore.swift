import Foundation
import Security

enum KeychainStore {
    private static let service = "com.nandanadileep.tictic"
    private static let account = "beta-installation-id"

    static func loadOrCreateInstallationID() throws -> String {
        if let existing = loadInstallationID(), !existing.isEmpty { return existing }
        let identifier = "TIC-INSTALL-\(UUID().uuidString.uppercased())"
        try saveInstallationID(identifier)
        return identifier
    }

    private static func saveInstallationID(_ identifier: String) throws {
        let value = Data(identifier.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = value
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private static func loadInstallationID() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)" }
}
