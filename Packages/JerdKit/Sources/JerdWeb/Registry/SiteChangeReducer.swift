import Foundation
import JerdFoundation

/// Computes the candidate configuration of one change. It saves nothing.
public struct SiteChangeReducer: Sendable {
    private let validator: SiteValidator
    private let hosts: any HostsFileReading

    public init(validator: SiteValidator = SiteValidator(), hosts: any HostsFileReading = SystemHostsFile()) {
        self.validator = validator
        self.hosts = hosts
    }

    /// The configuration after `change`. Validation errors leave everything unchanged.
    public func reduce(_ configuration: AppConfiguration, _ change: SiteChange) throws -> AppConfiguration {
        var next = configuration
        switch change {
        case .save(let draft, let confirmed):
            let site = try validator.validate(
                draft, existing: configuration.sites, hostsText: try hosts.read(), documentRootConfirmed: confirmed)
            if let index = next.sites.firstIndex(where: { $0.id == site.id }) {
                next.sites[index] = site
            } else {
                next.sites.append(site)
            }
        case .enabled(let id, let value):
            guard let index = next.sites.firstIndex(where: { $0.id == id }) else {
                throw JerdError.invalid("The site record is missing.")
            }
            next.sites[index].isEnabled = value
        case .remove(let id):
            next.sites.removeAll { $0.id == id }
        case .defaultRuntime(let id):
            guard next.runtimes.contains(where: { $0.id == id }) else {
                throw JerdError.invalid("The runtime record is missing.")
            }
            next.defaultRuntimeID = id
        case .caddy(let runtime):
            next.caddy = runtime
        case .upsertRuntime(let runtime):
            Self.upsert(runtime, into: &next)
        case .removeRuntime(let id):
            try Self.remove(runtime: id, from: &next)
        }
        return next
    }

    private static func upsert(_ inspected: DevelopmentRuntime, into configuration: inout AppConfiguration) {
        var runtime = inspected
        if let index = configuration.runtimes.firstIndex(where: {
            $0.cliPath == inspected.cliPath && $0.fpmPath == inspected.fpmPath
        }) {
            runtime.id = configuration.runtimes[index].id
            configuration.runtimes[index] = runtime
        } else {
            configuration.runtimes.append(runtime)
        }
        if configuration.defaultRuntimeID == nil { configuration.defaultRuntimeID = runtime.id }
    }

    private static func remove(runtime id: UUID, from configuration: inout AppConfiguration) throws {
        guard configuration.defaultRuntimeID != id,
            !configuration.sites.contains(where: { $0.phpSelection == .pinned(id) })
        else { throw JerdError.invalid("Reassign the default and all pinned sites before removing this runtime.") }
        configuration.runtimes.removeAll { $0.id == id }
    }
}
