import JerdFoundation

/// The route that one launch writes to `config.yml`. Only a resolved value can name a local
/// destination, so a launch never writes a route to a site that it did not resolve.
package enum TunnelRoute: Equatable, Sendable {
    /// The Cloudflare dashboard sends the route; `config.yml` is `{}`.
    case cloudflare
    /// One exact public hostname to a Jerd site, over loopback HTTPS with verified TLS.
    case site(PublicHostname, TunnelSiteDestination)
    /// One exact public hostname to a loopback HTTP or HTTPS address.
    case address(PublicHostname, origin: String)

    /// The resolved site, so Jerd can stop the route when the site changes.
    package var siteDestination: TunnelSiteDestination? {
        if case .site(_, let destination) = self { return destination }
        return nil
    }
}
