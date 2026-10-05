import Foundation

/// One connector for an existing, remotely managed Cloudflare tunnel. The hostname and the origin
/// are references for the user; Jerd never changes DNS or tunnel routes.
///
/// The stored keys are a compatibility contract: `id, name, hostname, siteID?, originURL?,
/// startOnLaunch, restartOnFailure, metricsPort`. Optional values are omitted when nil.
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
    /// Connect when Jerd opens. Saving a registration never connects.
    public var startOnLaunch: Bool
    /// Start a new connector after an unexpected exit, with backoff.
    public var restartOnFailure: Bool
    /// The loopback port of the connector's metrics and `/ready` endpoint.
    public var metricsPort: UInt16

    public init(
        id: UUID = UUID(), name: String, hostname: String, siteID: UUID? = nil, originURL: String? = nil,
        startOnLaunch: Bool = false, restartOnFailure: Bool = true, metricsPort: UInt16 = defaultMetricsPort
    ) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.siteID = siteID
        self.originURL = originURL
        self.startOnLaunch = startOnLaunch
        self.restartOnFailure = restartOnFailure
        self.metricsPort = metricsPort
    }

    /// `https://<hostname>`.
    public var publicURL: URL? { URL(string: "https://\(hostname)") }
}
