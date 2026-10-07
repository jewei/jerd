import Foundation

/// The Keychain item of one tunnel token. The service and account names are a compatibility contract.
package struct TunnelKeychainItem: Equatable, Hashable, Sendable {
    /// The generic-password service of every tunnel token.
    package static let tokenService = "dev.jerd.cloudflared.tunnel-token"

    /// `tokenService` in the app. Only the opt-in Keychain test uses another, throwaway service.
    package let service: String
    /// The registration UUID as an uppercase string.
    package let account: String

    package init(id: UUID, service: String = tokenService) {
        self.service = service
        account = id.uuidString
    }
}
