import Foundation
import JerdFoundation

/// The saved tunnel settings, `tunnels/settings.json`. Tokens are never part of it.
///
/// Required keys on decode: `schemaVersion` and `tunnels`. `runtime` is omitted when nil.
public struct TunnelConfiguration: Codable, Equatable, Sendable {
    /// The only format version that this build reads and writes.
    public static let currentSchemaVersion = 1
    /// The most registrations that one settings file holds.
    public static let maximumTunnels = 100

    public var schemaVersion = currentSchemaVersion
    public var runtime: TunnelRuntime?
    public var tunnels: [TunnelRegistration]

    public init(runtime: TunnelRuntime? = nil, tunnels: [TunnelRegistration] = []) {
        self.runtime = runtime
        self.tunnels = tunnels
    }

    /// Requires schema 1, at most 100 registrations with unique IDs and metrics ports, registrations
    /// that meet the stored rule (`TunnelRegistration.validateStored()`), and a valid runtime record.
    /// Load and every save use it. Save also checks the edited registration with the stricter
    /// `TunnelRegistration.validate()`.
    public func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion, tunnels.count <= Self.maximumTunnels,
            Set(tunnels.map(\.id)).count == tunnels.count,
            Set(tunnels.map(\.metricsPort)).count == tunnels.count
        else { throw JerdError.invalid(TunnelMessage.invalidConfiguration) }
        for tunnel in tunnels { try tunnel.validateStored() }
        try runtime?.validate()
    }

    /// The registration with `id`, or nil.
    public func registration(_ id: UUID) -> TunnelRegistration? {
        tunnels.first { $0.id == id }
    }

    /// A copy that adds `registration`, or replaces the one with its ID in place.
    func upserting(_ registration: TunnelRegistration) -> TunnelConfiguration {
        var next = self
        if let index = next.tunnels.firstIndex(where: { $0.id == registration.id }) {
            next.tunnels[index] = registration
        } else {
            next.tunnels.append(registration)
        }
        return next
    }
}
