import Foundation
import JerdFoundation
import Security

/// Keeps each tunnel token as a generic password in the user's Keychain.
///
/// The actor serializes the update-then-add sequence of a write, so two writes for one ID
/// cannot both try to add the item.
public actor TunnelSecretStore: TunnelSecretStoring {
    private let keychain: any KeychainAccessing

    public init() { keychain = SystemKeychain() }

    package init(keychain: any KeychainAccessing) { self.keychain = keychain }

    /// The token text, or nil when the item does not exist.
    public func read(id: UUID) throws -> String? {
        let result = keychain.copyData(TunnelKeychainItem(id: id))
        if result.status == errSecItemNotFound { return nil }
        guard result.status == errSecSuccess, let data = result.data, let token = String(data: data, encoding: .utf8)
        else { throw JerdError.unavailable(TunnelMessage.keychainRead(result.status)) }
        return token
    }

    /// Updates the item, or adds it when it does not exist yet.
    public func write(_ token: String, id: UUID) throws {
        let item = TunnelKeychainItem(id: id)
        let data = Data(token.utf8)
        let status = keychain.update(item, data: data)
        if status == errSecItemNotFound {
            guard keychain.add(item, data: data) == errSecSuccess else {
                throw JerdError.unavailable(TunnelMessage.keychainAdd)
            }
        } else if status != errSecSuccess {
            throw JerdError.unavailable(TunnelMessage.keychainUpdate(status))
        }
    }

    /// Deletes the item. A missing item is not an error.
    public func remove(id: UUID) throws {
        let status = keychain.delete(TunnelKeychainItem(id: id))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw JerdError.unavailable(TunnelMessage.keychainRemove(status))
        }
    }
}
