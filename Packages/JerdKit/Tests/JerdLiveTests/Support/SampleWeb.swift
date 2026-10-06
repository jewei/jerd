import Foundation
import JerdWeb

/// Fixed web records for the Sites tests.
enum SampleWeb {
    static let phpID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let siteID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    static func php(cli: String = "/runtimes/php/php", id: UUID = phpID) -> DevelopmentRuntime {
        DevelopmentRuntime(
            id: id, cliPath: cli, fpmPath: cli + "-fpm", version: "8.5.1", architectures: [.arm64],
            cliExtensions: ["json"], fpmExtensions: ["json"], inspectedAt: Date(timeIntervalSince1970: 0))
    }

    static func caddy(path: String = "/runtimes/caddy/caddy") -> CaddyRuntime {
        CaddyRuntime(path: path, version: "v2.11.4", architectures: [.arm64])
    }

    static func site() -> Site {
        Site(
            id: siteID, displayName: "Shop", projectPath: "/projects/shop", documentRoot: "/projects/shop/public",
            hostname: "shop.test")
    }

    static func configuration(
        sites: [Site] = [], php: DevelopmentRuntime? = nil, caddy: CaddyRuntime? = nil
    )
        -> AppConfiguration
    {
        AppConfiguration(sites: sites, runtimes: php.map { [$0] } ?? [], defaultRuntimeID: php?.id, caddy: caddy)
    }

    static func setup(hostnames: [String]) throws -> HTTPSSetup {
        HTTPSSetup(
            registration: HTTPSRegistration(
                installationID: Fixture.installationID, hostnames: hostnames,
                certificateDER: try Fixture.certificate(), trustPolicy: .serverTLS))
    }
}
