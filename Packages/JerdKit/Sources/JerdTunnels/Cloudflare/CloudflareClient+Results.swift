import Foundation

extension CloudflareClient {
    struct ZoneResult: Decodable {
        struct Account: Decodable { let id: String }

        let id: String
        let name: String
        let account: Account

        /// Nil for a zone with an ID that Jerd would refuse later.
        var zone: CloudflareZone? {
            guard CloudflareTunnelRecord.isIdentifier(id), CloudflareTunnelRecord.isIdentifier(account.id) else {
                return nil
            }
            return CloudflareZone(id: id, name: name.lowercased(), accountID: account.id)
        }
    }

    struct TunnelResult: Decodable {
        let id: UUID
        let deletedAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case deletedAt = "deleted_at"
        }
    }

    struct RecordResult: Decodable {
        let id: String
        let type: String?
        let content: String?

        /// True only for a CNAME to this tunnel: the only record that Jerd may delete.
        func routes(to tunnelID: UUID) -> Bool {
            type == "CNAME" && content?.lowercased() == CloudflareClient.routeTarget(tunnelID)
        }
    }

    struct RouteBody: Encodable {
        let type = "CNAME"
        let name: String
        let content: String
        let proxied = true
        let ttl = 1
        let comment: String
    }
}
