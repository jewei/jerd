import Foundation
import JerdTunnels
import Security
import Testing

/// Runs the real `SecItem` calls against the login Keychain. Opt-in, because it changes the
/// Keychain: `JERD_KEYCHAIN_INTEGRATION=1 swift test --filter TunnelKeychainIntegrationTests`.
///
/// It uses a throwaway service name, so it never reads or changes a real tunnel token, and it
/// deletes its item at the end, also when an expectation fails.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["JERD_KEYCHAIN_INTEGRATION"] == "1"))
struct TunnelKeychainIntegrationTests {
    @Test func theSystemKeychainAddsUpdatesReadsAndRemovesAToken() async throws {
        let service = "dev.jerd.tests.tunnel-token.\(UUID().uuidString)"
        let id = UUID()
        defer { Self.deleteItems(of: service) }
        let store = TunnelSecretStore(keychain: SystemKeychain(), service: service)
        #expect(try await store.read(id: id) == nil)
        try await store.write(TokenSamples.valid, id: id)
        #expect(try await store.read(id: id) == TokenSamples.valid)
        try await store.write(TokenSamples.rotated, id: id)
        #expect(try await store.read(id: id) == TokenSamples.rotated)
        #expect(Self.itemExists(service: service, account: id.uuidString.uppercased()))
        try await store.remove(id: id)
        #expect(try await store.read(id: id) == nil)
        try await store.remove(id: id)
    }

    /// True when a generic password with exactly this service and account exists. The file-based
    /// login Keychain does not report `kSecAttrAccessible`; the unit tests check that attribute
    /// in the add query.
    private static func itemExists(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    /// Deletes every item of the throwaway service.
    private static func deleteItems(of service: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
    }
}
