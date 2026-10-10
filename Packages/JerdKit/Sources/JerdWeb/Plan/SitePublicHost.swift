import Foundation
import JerdFoundation

/// An exact public hostname that a registered tunnel routes to one local site.
public struct SitePublicHost: Hashable, Sendable {
    public let siteID: UUID
    public let hostname: String

    public init(siteID: UUID, hostname: String) throws {
        let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
        guard hostname.utf8.count <= 253, labels.count >= 2,
            labels.allSatisfy({ label in
                !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                    && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
            }), hostname != "localhost", !hostname.hasSuffix(".localhost"),
            labels.last?.utf8.allSatisfy({ (48...57).contains($0) }) == false
        else { throw JerdError.invalid("Use a public tunnel hostname without a scheme, port, or wildcard.") }
        self.siteID = siteID
        self.hostname = hostname
    }
}
