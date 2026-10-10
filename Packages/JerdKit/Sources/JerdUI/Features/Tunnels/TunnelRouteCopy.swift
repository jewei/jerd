import JerdTunnels

/// The one wording of the route modes, so the editor and the tunnel page use the same terms.
///
/// Cloudflare calls a tunnel that its owner made with cloudflared "locally managed". Only such a
/// tunnel uses a route that Jerd sets; a tunnel from the dashboard uses the dashboard routes.
enum TunnelRouteCopy {
    /// The label of the route mode.
    static let label = "Route set by"

    /// Who sets the route.
    static func setter(_ routing: TunnelRouting) -> String {
        switch routing {
        case .local: "Jerd"
        case .cloudflare: "Cloudflare dashboard"
        }
    }

    /// The confirmation that Save needs in each mode.
    static func check(_ routing: TunnelRouting) -> String {
        switch routing {
        case .local: "I checked that this tunnel is locally managed."
        case .cloudflare: "I checked the existing route for this Mac."
        }
    }

    /// The title of the row that explains the confirmation.
    static func checkTitle(_ routing: TunnelRouting) -> String {
        switch routing {
        case .local: "Locally managed tunnel"
        case .cloudflare: "Cloudflare route"
        }
    }

    /// Why the confirmation matters: in both modes, Cloudflare can send traffic elsewhere.
    static func checkDetail(_ routing: TunnelRouting) -> String {
        switch routing {
        case .local:
            "A route that Jerd sets works only for a tunnel that you made with cloudflared. For a tunnel from the Cloudflare dashboard, cloudflared uses the dashboard routes instead."
        case .cloudflare:
            "Another connector can already serve this tunnel and share its traffic. Select Connect when you are ready."
        }
    }

    /// The footer of the destination in the editor.
    static func editorFooter(_ routing: TunnelRouting, linksSite: Bool) -> String {
        switch (routing, linksSite) {
        case (.cloudflare, _):
            "Jerd does not change this route. Make sure that the route in the Cloudflare dashboard points to this destination."
        case (.local, true):
            "Jerd sets this route when you connect, and cloudflared checks the site's HTTPS certificate. A changed route restarts all sites for a moment."
        case (.local, false):
            addressFooter
        }
    }

    /// The footer of the destination on the tunnel page.
    static func pageFooter(_ routing: TunnelRouting, linksSite: Bool) -> String {
        switch (routing, linksSite) {
        case (.cloudflare, _):
            "The Cloudflare dashboard sets this route. Jerd shows this destination for reference only."
        case (.local, true):
            "Jerd sets this route when you connect, and cloudflared checks the site's HTTPS certificate."
        case (.local, false):
            addressFooter
        }
    }

    /// Why "Connect when Jerd opens" is off for a Jerd route to a site.
    static let launchNote =
        "A tunnel with a route to a Jerd site connects only after you start the site. Select Connect then."

    private static let addressFooter =
        "Jerd sets this route when you connect. An HTTPS address must have a certificate that this Mac trusts."
}
