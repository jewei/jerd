import Foundation
import JerdFoundation
import Security

/// The Cloudflare account of the saved API token. The token lives only in the Keychain and in the
/// Authorization header of API requests.
public actor CloudflareAccount: CloudflareProvisioning {
    /// The Keychain service and account of the API token. They are a compatibility contract.
    package static let tokenItem = TunnelKeychainItem(service: "dev.jerd.cloudflare.api-token", account: "default")
    /// The longest API token that Jerd accepts, in bytes.
    package static let maximumTokenBytes = 512

    let keychain: any KeychainAccessing
    let transport: any CloudflareTransporting
    let item: TunnelKeychainItem

    public init() { self.init(keychain: SystemKeychain(), transport: CloudflareTransport()) }

    package init(
        keychain: any KeychainAccessing, transport: any CloudflareTransporting, item: TunnelKeychainItem = tokenItem
    ) {
        self.keychain = keychain
        self.transport = transport
        self.item = item
    }

    public func isConnected() throws -> Bool { try savedToken() != nil }

    public func connect(apiToken text: String) async throws -> [CloudflareZone] {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.utf8.count <= Self.maximumTokenBytes,
            token.utf8.allSatisfy({ (33...126).contains($0) })
        else { throw JerdError.invalid(CloudflareMessage.tokenFormat) }
        let zones = try await CloudflareClient(token: token, transport: transport).zones()
        guard !zones.isEmpty else { throw JerdError.invalid(CloudflareMessage.noZones) }
        try save(token)
        return zones
    }

    public func disconnect() throws {
        let status = keychain.delete(item)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw JerdError.unavailable(CloudflareMessage.keychainRemove(status))
        }
    }

    public func zones() async throws -> [CloudflareZone] {
        try await client().zones()
    }

    func client() throws -> CloudflareClient {
        guard let token = try savedToken() else { throw JerdError.unavailable(CloudflareMessage.notConnected) }
        return CloudflareClient(token: token, transport: transport)
    }

    private func savedToken() throws -> String? {
        let result = keychain.copyData(item)
        if result.status == errSecItemNotFound { return nil }
        guard result.status == errSecSuccess, let data = result.data, let token = String(data: data, encoding: .utf8)
        else { throw JerdError.unavailable(CloudflareMessage.keychainRead(result.status)) }
        return token
    }

    private func save(_ token: String) throws {
        let data = Data(token.utf8)
        let status = keychain.update(item, data: data)
        if status == errSecItemNotFound {
            let added = keychain.add(item, data: data)
            guard added == errSecSuccess else { throw JerdError.unavailable(CloudflareMessage.keychainAdd(added)) }
        } else if status != errSecSuccess {
            throw JerdError.unavailable(CloudflareMessage.keychainUpdate(status))
        }
    }
}
