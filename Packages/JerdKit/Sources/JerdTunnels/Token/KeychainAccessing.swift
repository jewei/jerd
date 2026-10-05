import Foundation

/// The four Keychain calls that the token store needs. Tests use a fake, so they never touch a real Keychain.
package protocol KeychainAccessing: Sendable {
    /// `SecItemCopyMatching` for the data of one item.
    func copyData(_ item: TunnelKeychainItem) -> (status: OSStatus, data: Data?)
    /// `SecItemUpdate` of the data of an existing item.
    func update(_ item: TunnelKeychainItem, data: Data) -> OSStatus
    /// `SecItemAdd` of a new item.
    func add(_ item: TunnelKeychainItem, data: Data) -> OSStatus
    /// `SecItemDelete` of one item.
    func delete(_ item: TunnelKeychainItem) -> OSStatus
}
