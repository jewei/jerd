import Foundation
import JerdFoundation

/// What Caddy needs about one site: its validated hostname, its paths, its FPM socket, and the
/// package hostnames that it restores from a forwarder.
package struct CaddySite: Equatable, Sendable {
    package let hostname: Hostname
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
        hostname: Hostname, projectPath: String, documentRoot: String, socket: URL, forwardedHosts: [PublicHostname]
    ) {
        self.hostname = hostname
        self.projectPath = projectPath
        self.documentRoot = documentRoot
        self.socket = socket
        self.forwardedHosts = forwardedHosts.sorted()
    }

    /// Laravel's `package/storage` link is package only when the document root is a separate folder.
    var servesProjectRoot: Bool { documentRoot == projectPath }
}
