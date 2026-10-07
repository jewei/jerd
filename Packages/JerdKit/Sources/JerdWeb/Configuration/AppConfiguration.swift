import Foundation
import JerdFoundation

/// The saved site configuration `configuration.json`: sites, PHP runtimes, the default runtime, and Caddy.
///
/// The property names and the synthesized coding are the compatibility contract. `ConfigurationCodec`
/// is the only reader and writer of the bytes.
public struct AppConfiguration: Codable, Equatable, Sendable {
    /// The schema that this build writes. Version 0 is read and migrated in memory.
    public static let currentVersion = 1

    public var schemaVersion = currentVersion
    public var sites: [Site] = []
    public var runtimes: [DevelopmentRuntime] = []
    /// Omitted from the JSON when nil.
    public var defaultRuntimeID: UUID?
    /// Omitted from the JSON when nil.
    public var caddy: CaddyRuntime?

    public init(
        sites: [Site] = [], runtimes: [DevelopmentRuntime] = [], defaultRuntimeID: UUID? = nil,
        caddy: CaddyRuntime? = nil
    ) {
        self.sites = sites
        self.runtimes = runtimes
        self.defaultRuntimeID = defaultRuntimeID
        self.caddy = caddy
    }

    /// The runtime that `site` selects: its pin, or the default. There is no fallback.
    /// - Throws: `.unavailable` when the selected runtime is not registered.
    public func runtime(for site: Site) throws -> DevelopmentRuntime {
        let selected: UUID?
        switch site.phpSelection {
        case .followDefault: selected = defaultRuntimeID
        case .pinned(let id): selected = id
        }
        guard let selected, let runtime = runtimes.first(where: { $0.id == selected }) else {
            throw JerdError.unavailable("The selected PHP runtime is unavailable. Select an installed runtime.")
        }
        return runtime
    }
}
