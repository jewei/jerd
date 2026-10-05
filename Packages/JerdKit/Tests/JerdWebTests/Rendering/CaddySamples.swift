import Foundation
import JerdFoundation

@testable import JerdWeb

/// The inputs of spec B Appendix A and of the loopback golden file.
enum CaddySamples {
    static let installationID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    static let storage = URL(fileURLWithPath: "/Users/u/Library/Application Support/Jerd/environment/certificates")

    /// `app.test` with a separate public root and `blog.test` served from its project root.
    static func appendixSites() throws -> [CaddySite] {
        [
            CaddySite(
                hostname: try Hostname("blog.test"), projectPath: "/p/blog", documentRoot: "/p/blog",
                socket: URL(fileURLWithPath: "/tmp/jerd-abcdef123456/php-1.sock")),
            CaddySite(
                hostname: try Hostname("app.test"), projectPath: "/p/app", documentRoot: "/p/app/public",
                socket: URL(fileURLWithPath: "/tmp/jerd-abcdef123456/php.sock")),
        ]
    }

    static func appendixOutput() throws -> Data {
        try CaddyConfigRenderer.render(
            sites: try appendixSites(), authority: .installation(installationID), storage: storage, binding: .product)
    }

    static func loopbackOutput() throws -> Data {
        let site = CaddySite(
            hostname: try Hostname("jerd-smoke.test"), projectPath: "/tmp/project space 项目",
            documentRoot: "/tmp/project space 项目", socket: URL(fileURLWithPath: "/tmp/jerd-test/php-0.sock"))
        return try CaddyConfigRenderer.render(
            sites: [site], authority: .isolatedTest, storage: URL(fileURLWithPath: "/tmp/run café/certificates"),
            binding: ListenerBinding(httpsPort: 18_443, httpPort: 18_080, inherited: false))
    }
}
