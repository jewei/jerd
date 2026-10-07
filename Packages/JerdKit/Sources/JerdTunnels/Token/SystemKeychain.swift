import Foundation
import Security

/// The login Keychain of the current user, through the `SecItem` functions.
package struct SystemKeychain: KeychainAccessing {
    package init() {}

    package func copyData(_ item: TunnelKeychainItem) -> (status: OSStatus, data: Data?) {
        var query = Self.query(item)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        return (status, value as? Data)
    }

    package func update(_ item: TunnelKeychainItem, data: Data) -> OSStatus {
        let changes = [kSecValueData as String: data] as CFDictionary
        return SecItemUpdate(Self.query(item) as CFDictionary, changes)
    }

    package func add(_ item: TunnelKeychainItem, data: Data) -> OSStatus {
        SecItemAdd(Self.addAttributes(item, data: data) as CFDictionary, nil)
    }

    package func delete(_ item: TunnelKeychainItem) -> OSStatus {
        SecItemDelete(Self.query(item) as CFDictionary)
    }

    /// A generic password with the tunnel-token service and the registration account.
    package static func query(_ item: TunnelKeychainItem) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: item.service,
            kSecAttrAccount as String: item.account,
        ]
    }

    /// A new item stays on this Mac and is readable after the first unlock, so a connector can
    /// start when Jerd opens at login.
    package static func addAttributes(_ item: TunnelKeychainItem, data: Data) -> [String: Any] {
        var attributes = query(item)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return attributes
    }
}
