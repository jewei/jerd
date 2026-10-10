import Foundation
import JerdFoundation

/// What Caddy needs about one site: its validated hostname, its paths, its FPM socket, and the
/// public hostnames that it restores from a forwarder.
public struct CaddySite: Equatable, Sendable {
    public let hostname: Hostname
    public let projectPath: String
    public let documentRoot: String
    public let socket: URL
    /// Sorted, so the output is deterministic (`ForwardedHostRoutePolicy`).
    package let forwardedHosts: [PublicHostname]

    public init(hostname: Hostname, projectPath: String, documentRoot: String, socket: URL) {
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

    /// Laravel's `public/storage` link is public only when the document root is a separate folder.
    var servesProjectRoot: Bool { documentRoot == projectPath }
}
