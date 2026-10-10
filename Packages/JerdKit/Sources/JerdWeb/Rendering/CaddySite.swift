import Foundation
import JerdFoundation

/// What Caddy needs about one site: its validated hostname, its paths, and its FPM socket.
public struct CaddySite: Equatable, Sendable {
    public let hostname: Hostname
    public let projectPath: String
    public let documentRoot: String
    public let socket: URL
    public let publicHosts: Set<SitePublicHost>

    public init(
        hostname: Hostname, projectPath: String, documentRoot: String, socket: URL,
        publicHosts: Set<SitePublicHost> = []
    ) {
        self.hostname = hostname
        self.projectPath = projectPath
        self.documentRoot = documentRoot
        self.socket = socket
        self.publicHosts = publicHosts
    }

    /// Laravel's `public/storage` link is public only when the document root is a separate folder.
    var servesProjectRoot: Bool { documentRoot == projectPath }
}
