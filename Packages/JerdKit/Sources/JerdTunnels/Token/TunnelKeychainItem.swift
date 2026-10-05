import Foundation

/// The Keychain item of one tunnel token. The service and account names are a compatibility contract.
package struct TunnelKeychainItem: Equatable, Hashable, Sendable {
    /// The generic-password service of every tunnel token.
    package static let service = "dev.jerd.cloudflared.tunnel-token"

    /// The registration UUID as an uppercase string.
    package let account: String

    package init(id: UUID) { account = id.uuidString }
}
