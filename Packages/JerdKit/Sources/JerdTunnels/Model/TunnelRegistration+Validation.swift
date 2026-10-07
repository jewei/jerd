import Foundation
import JerdFoundation

extension TunnelRegistration {
    /// The loopback hosts that an origin address may use.
    static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// Checks a new or edited registration: the name, the metrics port, the public hostname, and the
    /// origin reference. Save uses this rule.
    ///
    /// It is stricter than `validateStored()`: it also refuses an IPv4 literal as hostname.
    /// A saved registration that breaks only this rule still loads, and
    /// `TunnelSnapshot.settingsIssue` asks the user to edit it.
    public func validate() throws {
        try validateStored()
        guard !Self.isAddressLiteral(hostname) else { throw JerdError.invalid(TunnelMessage.addressHostname) }
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

    private func validateNameAndPort() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
            !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
            metricsPort > 1_023
        else { throw JerdError.invalid(TunnelMessage.invalidName) }
    }

    /// The rule of earlier builds: at most 253 bytes; two or more labels of 1 to 63 bytes of
    /// `a-z 0-9 -` that do not start or end with `-`; not `localhost` or a name below it; not `127.0.0.1`.
    static func isWellFormedHostname(_ hostname: String) -> Bool {
        let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
        guard hostname.utf8.count <= 253, labels.count >= 2 else { return false }
        let wellFormed = labels.allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }
        return wellFormed && hostname != "localhost" && !hostname.hasSuffix(".localhost") && hostname != "127.0.0.1"
    }

    /// True for an IPv4 literal: a dotted name whose last label is all digits. No top-level domain
    /// is numeric, so such a name cannot be a public hostname.
    static func isAddressLiteral(_ hostname: String) -> Bool {
        guard let last = hostname.split(separator: ".", omittingEmptySubsequences: false).last, !last.isEmpty
        else { return false }
        return last.utf8.allSatisfy { (48...57).contains($0) }
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
