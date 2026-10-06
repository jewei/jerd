import JerdWeb

/// The bundled PHP and Caddy: whether they must be installed, and their inspected records.
/// `BundledDevelopmentSource` is the live type.
package protocol DevelopmentRuntimeSource: Sendable {
    /// True when PHP or Caddy is not configured, or the CLI tools record misses a version.
    /// - Throws: When the CLI tools record is corrupt. It stays as it is.
    func isNeeded(for configuration: AppConfiguration) async throws -> Bool
    /// Installs PHP, Caddy, Composer, and the Laravel installer, then inspects PHP and Caddy.
    func install() async throws -> DevelopmentRuntimeRecords
}
