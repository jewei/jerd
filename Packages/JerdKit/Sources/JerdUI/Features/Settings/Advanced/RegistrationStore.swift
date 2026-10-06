import Foundation
import JerdWeb
import Observation

/// The registered PHP runtimes, the default PHP, and the registered Caddy: the one source of
/// truth that Runtimes, Advanced, and the dashboard read. Every change goes through this store
/// and reads the registrations again, so a change on one page shows on every page at once.
@MainActor
@Observable
public final class RegistrationStore {
    public private(set) var registrations = LocalRuntimeRegistrations()
    @ObservationIgnored private let port: any ExecutableRegistrationPort

    public init(port: any ExecutableRegistrationPort) {
        self.port = port
    }

    /// The default PHP runtime, if one is registered.
    public var defaultPHP: DevelopmentRuntime? {
        registrations.php.first { $0.id == registrations.defaultPHPID }
    }

    /// Reads the registrations of the site configuration. A failure keeps the old values.
    public func reload() async throws {
        registrations = try await port.registrations()
    }

    public func setDefaultPHP(_ id: UUID) async throws {
        try await change { try await $0.setDefaultPHP(id) }
    }

    public func importPHP(cli: URL, fpm: URL) async throws {
        try await change { try await $0.importPHP(cli: cli, fpm: fpm) }
    }

    public func importCaddy(_ executable: URL) async throws {
        try await change { try await $0.importCaddy(executable) }
    }

    /// Removes a PHP registration. The runtime files stay on disk.
    public func removePHP(_ id: UUID) async throws {
        try await change { try await $0.removePHP(id) }
    }

    /// Runs one change, then reads the registrations again, also after a failure: a failed
    /// change can still have changed part of the configuration.
    private func change(_ body: (any ExecutableRegistrationPort) async throws -> Void) async throws {
        do {
            try await body(port)
        } catch {
            try? await reload()
            throw error
        }
        try await reload()
    }
}
