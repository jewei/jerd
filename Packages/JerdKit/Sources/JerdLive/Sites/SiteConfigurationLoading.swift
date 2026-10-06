import JerdWeb

/// The site registry calls that the live ports use. `SiteRegistry` is the live type.
package protocol SiteConfigurationLoading: Sendable {
    func load() async throws -> AppConfiguration
    func snapshot() async throws -> AppConfiguration
}

extension SiteRegistry: SiteConfigurationLoading {}
