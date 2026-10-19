import Foundation
import JerdFoundation

/// What Caddy needs about one site: its validated hostname and aliases, its paths, its FPM socket,
/// and the public hostnames that it restores from a forwarder.
package struct CaddySite: Equatable, Sendable {
    package let hostname: Hostname
    /// Sorted, like the saved aliases.
    package let aliases: [Hostname]
    package let projectPath: String
    package let documentRoot: String
    package let socket: URL
    /// Sorted, so the output is deterministic (`ForwardedHostRoutePolicy`).
    package let forwardedHosts: [PublicHostname]

    package init(hostname: Hostname, projectPath: String, documentRoot: String, socket: URL) {
        self.init(
            hostname: hostname, projectPath: projectPath, documentRoot: documentRoot, socket: socket, forwardedHosts: []
        )
    }

    package init(
        hostname: Hostname, projectPath: String, documentRoot: String, socket: URL, forwardedHosts: [PublicHostname],
        aliases: [Hostname] = []
    ) {
        self.hostname = hostname
        self.aliases = aliases.sorted()
        self.projectPath = projectPath
        self.documentRoot = documentRoot
        self.socket = socket
        self.forwardedHosts = forwardedHosts.sorted()
    }

    /// The main hostname first, then the aliases.
    var servedHostnames: [Hostname] { [hostname] + aliases }

    /// Laravel's `package/storage` link is package only when the document root is a separate folder.
    var servesProjectRoot: Bool { documentRoot == projectPath }
}
