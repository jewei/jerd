import Foundation
import JerdFoundation

/// The Cloudflare resources that Jerd created for a tunnel. Only a registration with this record
/// can delete its tunnel and DNS record in Cloudflare.
///
/// The stored keys are a compatibility contract: `accountID, tunnelID, zoneID, dnsRecordID`.
public struct CloudflareTunnelRecord: Codable, Equatable, Hashable, Sendable {
    public let accountID: String
    public let tunnelID: UUID
    public let zoneID: String
    public let dnsRecordID: String

    public init(accountID: String, tunnelID: UUID, zoneID: String, dnsRecordID: String) {
        self.accountID = accountID
        self.tunnelID = tunnelID
        self.zoneID = zoneID
        self.dnsRecordID = dnsRecordID
    }

    /// Cloudflare IDs are 32 lower-case hexadecimal characters. A path segment must never carry
    /// another character.
    package static func isIdentifier(_ text: String) -> Bool {
        text.utf8.count == 32 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    package func validate() throws {
        guard [accountID, zoneID, dnsRecordID].allSatisfy(Self.isIdentifier) else {
            throw JerdError.invalid(CloudflareMessage.invalidRecord)
        }
    }
}
