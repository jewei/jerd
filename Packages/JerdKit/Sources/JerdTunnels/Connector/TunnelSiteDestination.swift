import Foundation
import JerdFoundation

/// A linked Jerd site as the web run serves it now, resolved for one connector launch.
package struct TunnelSiteDestination: Hashable, Sendable {
    /// The site that the route sends to. Jerd stops the route when the run stops serving it.
    package let siteID: UUID
    /// The site's `.test` name: the Host header and the TLS server name of each request.
    package let hostname: Hostname
    /// The port of Jerd's HTTPS listener on `127.0.0.1`.
    package let httpsPort: UInt16
    /// The installation CA, so cloudflared verifies the site's certificate.
    package let certificateAuthorityFile: URL

    package init(siteID: UUID, hostname: Hostname, httpsPort: UInt16, certificateAuthorityFile: URL) {
        self.siteID = siteID
        self.hostname = hostname
        self.httpsPort = httpsPort
        self.certificateAuthorityFile = certificateAuthorityFile
    }

    /// The cloudflared service of the route: Jerd's loopback HTTPS listener.
    var service: String { "https://127.0.0.1:\(httpsPort)" }
}
