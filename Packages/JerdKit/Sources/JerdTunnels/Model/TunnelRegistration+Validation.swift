import Foundation
import JerdFoundation

extension TunnelRegistration {
    /// The loopback hosts that an origin address may use.
    static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// Checks the name, the metrics port, the public hostname, and the origin reference.
    public func validate() throws {
        try validateNameAndPort()
        guard Self.isPublicHostname(hostname) else { throw JerdError.invalid(TunnelMessage.invalidHostname) }
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

    /// At most 253 bytes; two or more labels of 1 to 63 bytes of `a-z 0-9 -` that do not start or end
    /// with `-`; not `localhost` or a name below it; and not an IPv4 literal. A dotted name whose last
    /// label is all digits is an IPv4 literal, because no top-level domain is numeric.
    static func isPublicHostname(_ hostname: String) -> Bool {
        let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
        guard hostname.utf8.count <= 253, labels.count >= 2, let last = labels.last else { return false }
        let wellFormed = labels.allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }
        let numericTopLevel = last.utf8.allSatisfy { (48...57).contains($0) }
        return wellFormed && !numericTopLevel && hostname != "localhost" && !hostname.hasSuffix(".localhost")
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
