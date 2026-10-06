import Foundation
import JerdUI
import JerdWeb

/// The `ExecutableRegistrationPort` of Advanced: local PHP and Caddy records in the site
/// configuration. Every change goes through the site change transaction, so running sites
/// follow it. Removing a registration never deletes files.
package struct LiveExecutableRegistrations: ExecutableRegistrationPort {
    let configuration: any SiteConfigurationReading
    let sites: any SiteChangeApplying
    let inspector: any ExecutableInspecting

    package init(
        configuration: any SiteConfigurationReading, sites: any SiteChangeApplying, inspector: any ExecutableInspecting
    ) {
        self.configuration = configuration
        self.sites = sites
        self.inspector = inspector
    }

    package init(domain: LiveDomain) {
        self.init(
            configuration: domain.developmentRuntimes, sites: domain.web.transaction,
            inspector: ExecutableInspector(layout: domain.layout))
    }

    package func registrations() async throws -> LocalRuntimeRegistrations {
        let loaded = try await configuration.loadConfiguration()
        return Self.registrations(loaded, setupMessage: await configuration.message)
    }

    package func importPHP(cli: URL, fpm: URL) async throws {
        try await commit(.upsertRuntime(try await inspector.inspectPHP(cli: cli, fpm: fpm)))
    }

    package func importCaddy(_ executable: URL) async throws {
        try await commit(.caddy(try await inspector.inspectCaddy(executable)))
    }

    package func removePHP(_ id: UUID) async throws {
        try await commit(.removeRuntime(id))
    }

    package func setDefaultPHP(_ id: UUID) async throws {
        try await commit(.defaultRuntime(id))
    }

    /// The Advanced view of a configuration.
    package static func registrations(
        _ configuration: AppConfiguration, setupMessage: String?
    ) -> LocalRuntimeRegistrations {
        LocalRuntimeRegistrations(
            php: configuration.runtimes, defaultPHPID: configuration.defaultRuntimeID,
            caddyVersion: configuration.caddy?.version, setupMessage: setupMessage)
    }

    private func commit(_ change: SiteChange) async throws {
        _ = try SiteChangeCommit.require(try await sites.apply(change, startIfStopped: false))
    }
}
