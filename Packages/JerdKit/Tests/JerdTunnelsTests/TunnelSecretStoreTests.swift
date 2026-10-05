import Foundation
import JerdFoundation
import JerdTunnels
import Security
import Testing

@Suite struct TunnelSecretStoreTests {
    private let id = UUID(uuidString: "32394787-9B89-41AE-A065-57520475754A") ?? UUID()

    @Test func theItemUsesTheCompatibleServiceAndUppercaseAccount() {
        let item = TunnelKeychainItem(id: UUID(uuidString: "c52b93c8-ad2f-4f26-9252-9195bb7e236a") ?? UUID())
        #expect(TunnelKeychainItem.tokenService == "dev.jerd.cloudflared.tunnel-token")
        #expect(item.service == TunnelKeychainItem.tokenService)
        #expect(item.account == "C52B93C8-AD2F-4F26-9252-9195BB7E236A")
        let query = SystemKeychain.query(item)
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "dev.jerd.cloudflared.tunnel-token")
        #expect(query[kSecAttrAccount as String] as? String == item.account)
    }

    @Test func aNewItemIsDeviceOnlyAndReadableAfterFirstUnlock() {
        let attributes = SystemKeychain.addAttributes(TunnelKeychainItem(id: id), data: Data("token".utf8))
        #expect(
            attributes[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(attributes[kSecValueData as String] as? Data == Data("token".utf8))
    }

    @Test func aWriteUpdatesFirstAndAddsOnlyWhenTheItemIsMissing() async throws {
        let keychain = FakeKeychain()
        let store = TunnelSecretStore(keychain: keychain)
        try await store.write("first", id: id)
        try await store.write("second", id: id)
        #expect(try await store.read(id: id) == "second")
        let account = id.uuidString
        #expect(
            keychain.state.withLock(\.calls) == [
                "update \(account)", "add \(account)", "update \(account)", "copy \(account)",
            ])
    }

    @Test func aMissingItemReadsAsNilAndRemovesWithoutError() async throws {
        let store = TunnelSecretStore(keychain: FakeKeychain())
        #expect(try await store.read(id: id) == nil)
        try await store.remove(id: id)
    }

    @Test func keychainFailuresKeepTheirMessagesAndStatus() async {
        let keychain = FakeKeychain()
        keychain.state.withLock { $0.forcedStatus = errSecInteractionNotAllowed }
        let store = TunnelSecretStore(keychain: keychain)
        let status = errSecInteractionNotAllowed
        await #expect(throws: JerdError.unavailable("Cannot read the tunnel token from Keychain (\(status)).")) {
            try await store.read(id: id)
        }
        await #expect(throws: JerdError.unavailable("Cannot update the tunnel token in Keychain (\(status)).")) {
            try await store.write("token", id: id)
        }
        await #expect(throws: JerdError.unavailable("Cannot remove the tunnel token from Keychain (\(status)).")) {
            try await store.remove(id: id)
        }
    }

    @Test func aFailedAddIsReported() async {
        let keychain = FakeKeychain()
        let store = TunnelSecretStore(keychain: BrokenAddKeychain(base: keychain))
        await #expect(throws: JerdError.unavailable("Cannot save the tunnel token in Keychain.")) {
            try await store.write("token", id: id)
        }
    }
}

/// Reports a missing item on update and then refuses the add.
private struct BrokenAddKeychain: KeychainAccessing {
    let base: FakeKeychain

    func copyData(_ item: TunnelKeychainItem) -> (status: OSStatus, data: Data?) { base.copyData(item) }
    func update(_ item: TunnelKeychainItem, data: Data) -> OSStatus { errSecItemNotFound }
    func add(_ item: TunnelKeychainItem, data: Data) -> OSStatus { errSecNotAvailable }
    func delete(_ item: TunnelKeychainItem) -> OSStatus { base.delete(item) }
}
