import Foundation
import Security

public protocol TunnelSecretStoring: Sendable {
    func read(id: UUID) async throws -> String?
    func write(_ token: String, id: UUID) async throws
    func remove(id: UUID) async throws
}

public actor TunnelKeychainStore: TunnelSecretStoring {
    private let service = "dev.jerd.cloudflared.tunnel-token"
    public init() {}
    public func read(id: UUID) throws -> String? {
        var query = attributes(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data, let token = String(data: data, encoding: .utf8) else {
            throw JerdError.unavailable("Cannot read the tunnel token from Keychain (\(status)).")
        }
        return token
    }
    public func write(_ token: String, id: UUID) throws {
        let query = attributes(id)
        let changes = [kSecValueData as String: Data(token.utf8)] as [String: Any]
        let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(changes) { _, value in value }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw JerdError.unavailable("Cannot save the tunnel token in Keychain.") }
        } else if status != errSecSuccess { throw JerdError.unavailable("Cannot update the tunnel token in Keychain (\(status)).") }
    }
    public func remove(id: UUID) throws {
        let status = SecItemDelete(attributes(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw JerdError.unavailable("Cannot remove the tunnel token from Keychain (\(status)).") }
    }
    private func attributes(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
    }
}
