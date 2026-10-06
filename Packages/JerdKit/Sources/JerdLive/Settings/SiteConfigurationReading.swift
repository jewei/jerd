import JerdWeb

/// The loaded site configuration and the result of the bundled PHP and Caddy setup.
/// `DevelopmentRuntimeSetup` is the live type, so Settings reads the configuration only after
/// the bundled runtimes are in place.
package protocol SiteConfigurationReading: Sendable {
    func loadConfiguration() async throws -> AppConfiguration
    /// The bundled setup message, or nil before the first successful load.
    var message: String? { get async }
}

extension DevelopmentRuntimeSetup: SiteConfigurationReading {}
