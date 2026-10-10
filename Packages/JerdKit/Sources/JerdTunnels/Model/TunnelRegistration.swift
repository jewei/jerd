import Foundation

/// One connector for an existing Cloudflare tunnel. Local routing configures only this connector.
///
/// The stored keys are a compatibility contract: `id, name, hostname, siteID?, originURL?,
/// startOnLaunch, restartOnFailure, metricsPort, routing?`. Missing routing means Cloudflare.
public struct TunnelRegistration: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// The first metrics port that Jerd suggests.
    public static let defaultMetricsPort: UInt16 = 20_241

    public let id: UUID
    public var name: String
    /// The public hostname that the Cloudflare route serves, for example `preview.example.com`.
    public var hostname: String
    /// The registered Jerd site that the route points to, when the user chose one.
    public var siteID: UUID?
    /// A local HTTP or HTTPS address that the route points to, when no site is chosen.
    public var originURL: String?
    /// Earlier registrations keep Cloudflare routing until the user chooses local routing.
    public var routing: TunnelRouting
    /// Connect when Jerd opens. Saving a registration never connects.
    public var startOnLaunch: Bool
    /// Start a new connector after an unexpected exit, with backoff.
    public var restartOnFailure: Bool
    /// The loopback port of the connector's metrics and `/ready` endpoint.
    public var metricsPort: UInt16

    public init(
        id: UUID = UUID(), name: String, hostname: String, siteID: UUID? = nil, originURL: String? = nil,
        startOnLaunch: Bool = false, restartOnFailure: Bool = true, metricsPort: UInt16 = defaultMetricsPort,
        routing: TunnelRouting = .cloudflare
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.siteID = siteID
        self.originURL = originURL
        self.routing = routing
        self.startOnLaunch = startOnLaunch
        self.restartOnFailure = restartOnFailure
        self.metricsPort = metricsPort
    }

    /// `https://<hostname>`.
    public var publicURL: URL? { URL(string: "https://\(hostname)") }
}
