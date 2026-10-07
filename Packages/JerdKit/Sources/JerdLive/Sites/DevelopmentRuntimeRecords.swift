import JerdWeb

/// The records of the installed bundled PHP and Caddy.
package struct DevelopmentRuntimeRecords: Equatable, Sendable {
    package let php: DevelopmentRuntime
    package let caddy: CaddyRuntime

    package init(php: DevelopmentRuntime, caddy: CaddyRuntime) {
        self.php = php
        self.caddy = caddy
    }

    /// The changes that register the records: PHP always (the reducer makes it the default when
    /// none is set), Caddy only when none is selected, so a user's own Caddy stays.
    package func changes(for configuration: AppConfiguration) -> [SiteChange] {
        [.upsertRuntime(php)] + (configuration.caddy == nil ? [.caddy(caddy)] : [])
    }
}
