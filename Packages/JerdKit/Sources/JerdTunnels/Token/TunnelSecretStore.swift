import Foundation
import JerdFoundation
import Security

/// Keeps each tunnel token as a generic password in the user's Keychain.
///
/// The actor serializes the update-then-add sequence of a write, so two writes for one ID
/// cannot both try to add the item.
public actor TunnelSecretStore: TunnelSecretStoring {
    private let keychain: any KeychainAccessing
    private let service: String

    public init() { self.init(keychain: SystemKeychain()) }

    /// `service` is `TunnelKeychainItem.tokenService` except in the opt-in Keychain test.
    package init(keychain: any KeychainAccessing, service: String = TunnelKeychainItem.tokenService) {
        self.keychain = keychain
        self.service = service
    }

    /// The token text, or nil when the item does not exist.
    public func read(id: UUID) throws -> String? {
        let result = keychain.copyData(keychainItem(id))
        if result.status == errSecItemNotFound { return nil }
        guard result.status == errSecSuccess, let data = result.data, let token = String(data: data, encoding: .utf8)
        else { throw JerdError.unavailable(TunnelMessage.keychainRead(result.status)) }
        return token
    }

    /// Updates the item, or adds it when it does not exist yet.
    public func write(_ token: String, id: UUID) throws {
        let item = keychainItem(id)
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
        let status = keychain.delete(keychainItem(id))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw JerdError.unavailable(TunnelMessage.keychainRemove(status))
        }
    }

    private func keychainItem(_ id: UUID) -> TunnelKeychainItem { TunnelKeychainItem(id: id, service: service) }
}
