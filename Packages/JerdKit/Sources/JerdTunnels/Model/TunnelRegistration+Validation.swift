import Foundation
import JerdFoundation

extension TunnelRegistration {
    /// The loopback hosts that an origin address may use.
    static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// Checks a new or edited registration: the name, the metrics port, the public hostname, the
    /// origin reference, and a local route. Save uses this rule.
    ///
    /// It is stricter than `validateStored()`: the hostname must be a `PublicHostname`, so an IPv4
    /// literal or a `.test` name is refused. A saved registration that breaks only this rule still
    /// loads, and `TunnelSnapshot.settingsIssue` asks the user to edit it.
    public func validate() throws {
        try validateStored()
        guard PublicHostname(hostname) != nil else {
            // The stored rule already refused every other name that is not a public hostname.
            let message =
                PublicHostname.isAddressLiteral(hostname) ? TunnelMessage.addressHostname : TunnelMessage.localHostname
            throw JerdError.invalid(message)
        }
        if routing == .local { try validateLocalRoute() }
    }

    /// Checks a registration from the settings file with the rule of earlier builds, so a file that
    /// they wrote still loads. Load, and the saves that keep other registrations, use this rule.
    package func validateStored() throws {
        try validateNameAndPort()
        guard Self.isWellFormedHostname(hostname) else { throw JerdError.invalid(TunnelMessage.invalidHostname) }
        if let originURL, siteID != nil || !Self.isLocalOrigin(originURL) {
            throw JerdError.invalid(TunnelMessage.invalidOrigin)
        }
    }

    /// A local route needs a destination. cloudflared sends the request path unchanged, so an
    /// address with a path (also `/`) or a query cannot work; cloudflared refuses a path itself.
    private func validateLocalRoute() throws {
        guard siteID != nil || originURL != nil else { throw JerdError.invalid(TunnelMessage.localDestinationMissing) }
        if let originURL, let address = URLComponents(string: originURL), !address.path.isEmpty || address.query != nil
        {
            throw JerdError.invalid(TunnelMessage.localAddressPath)
        }
    }

    private func validateNameAndPort() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
            !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
            metricsPort > 1_023
        else { throw JerdError.invalid(TunnelMessage.invalidName) }
    }

    /// The rule of earlier builds: DNS syntax (`HostnamePolicy.isDNSName(_:)`), not a name below
    /// `localhost`, and not `127.0.0.1`.
    static func isWellFormedHostname(_ hostname: String) -> Bool {
        HostnamePolicy.isDNSName(hostname) && !hostname.hasSuffix(".localhost") && hostname != "127.0.0.1"
    }

    /// An `http` or `https` URL on a loopback host, without credentials or a fragment, with a valid port.
    static func isLocalOrigin(_ text: String) -> Bool {
        guard let components = URLComponents(string: text), let scheme = components.scheme,
            ["http", "https"].contains(scheme), let host = components.host, localHosts.contains(host)
        else { return false }
        let portIsValid = components.port.map { (1...65_535).contains($0) } ?? true
        return components.user == nil && components.password == nil && components.fragment == nil && portIsValid
    }
}
