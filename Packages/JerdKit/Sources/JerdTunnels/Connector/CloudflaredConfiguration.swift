import Foundation
import JerdFoundation

/// A private connector configuration with one exact hostname and a rejecting fallback.
package enum CloudflaredConfiguration {
    /// JSON is also valid YAML and safely quotes paths and user-supplied addresses.
    package static func render(_ registration: TunnelRegistration, site: TunnelSiteDestination? = nil) throws -> Data {
        guard registration.routing == .local else { return CloudflaredCommand.emptyConfiguration }
        try registration.validate()
        var rule: [String: Any] = ["hostname": registration.hostname]
        if registration.siteID != nil {
            guard let site else {
                throw JerdError.unavailable("Load the selected Jerd site before connecting this tunnel.")
            }
            _ = try Hostname(site.hostname)
            guard site.certificateAuthority.isFileURL else {
                throw JerdError.invalid("The site's certificate authority must be a local file.")
            }
            rule["service"] = "https://127.0.0.1:443"
            rule["originRequest"] = [
                "httpHostHeader": site.hostname,
                "originServerName": site.hostname,
                "caPool": site.certificateAuthority.path,
                "noTLSVerify": false,
            ]
        } else {
            rule["service"] = registration.originURL
        }
        return try JSONSerialization.data(
            withJSONObject: ["ingress": [rule, ["service": "http_status:404"]]],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}
