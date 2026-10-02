import Foundation

/// Serializes validation and persistence. The UI gets a snapshot only after a successful save.
public actor SiteRegistry {
    private let store: any ConfigurationStore
    private var configuration = AppConfiguration()
    private var loaded = false
    private var writing = false
    public init(store: any ConfigurationStore) { self.store = store }

    public func snapshot() throws -> AppConfiguration {
        guard loaded else { throw JerdError.corruptConfiguration("Load valid site settings before making changes.") }
        return configuration
    }

    public func propose(_ change: SiteConfigurationChange) throws -> AppConfiguration {
        var next = try snapshot()
        switch change {
        case .save(let draft, let confirmed):
            let hosts = try String(contentsOfFile: "/etc/hosts", encoding: .utf8)
            let site = try SiteValidator().validate(draft, existing: configuration.sites, hostsContents: hosts, documentRootConfirmed: confirmed)
            if let index = next.sites.firstIndex(where: { $0.id == site.id }) { next.sites[index] = site }
            else { next.sites.append(site) }
        case .enabled(let id, let value):
            guard let index = next.sites.firstIndex(where: { $0.id == id }) else { throw JerdError.invalid("The site record is missing.") }
            next.sites[index].isEnabled = value
        case .remove(let id): next.sites.removeAll { $0.id == id }
        case .defaultRuntime(let id):
            guard next.runtimes.contains(where: { $0.id == id }) else { throw JerdError.invalid("The runtime record is missing.") }
            next.defaultRuntimeID = id
        case .caddy(let runtime): next.caddy = runtime
        }
        return next
    }

    public func replace(_ next: AppConfiguration, expecting previous: AppConfiguration) async throws -> AppConfiguration {
        guard configuration == previous else { throw JerdError.unavailable("The site settings changed. Review the edit again.") }
        return try await commit(next)
    }

    public func load() async throws -> AppConfiguration {
        guard !writing else { throw JerdError.invalid("A configuration operation is in progress.") }
        writing = true
        defer { writing = false }
        let result = try await store.load()
        configuration = result
        loaded = true
        return result
    }

    public func suggestRoot(_ path: String) throws -> DocumentRootSuggestion {
        try SiteValidator().suggestDocumentRoot(projectPath: path)
    }

    public func saveSite(_ draft: Site, documentRootConfirmed: Bool) async throws -> AppConfiguration {
        let hosts = try String(contentsOfFile: "/etc/hosts", encoding: .utf8)
        let site = try SiteValidator().validate(draft, existing: configuration.sites, hostsContents: hosts,
                                                documentRootConfirmed: documentRootConfirmed)
        var next = configuration
        if let index = next.sites.firstIndex(where: { $0.id == site.id }) { next.sites[index] = site }
        else { next.sites.append(site) }
        return try await commit(next)
    }

    public func removeSite(_ id: UUID) async throws -> AppConfiguration {
        var next = configuration
        next.sites.removeAll { $0.id == id }
        return try await commit(next)
    }

    public func setEnabled(_ id: UUID, enabled: Bool) async throws -> AppConfiguration {
        var next = configuration
        guard let index = next.sites.firstIndex(where: { $0.id == id }) else { throw JerdError.invalid("Site record is missing.") }
        next.sites[index].isEnabled = enabled
        return try await commit(next)
    }

    public func addRuntime(_ inspected: DevelopmentRuntime) async throws -> AppConfiguration {
        var next = configuration
        var runtime = inspected
        if let index = next.runtimes.firstIndex(where: { $0.cliPath == inspected.cliPath && $0.fpmPath == inspected.fpmPath }) {
            runtime.id = next.runtimes[index].id
            next.runtimes[index] = runtime
        } else { next.runtimes.append(runtime) }
        if next.defaultRuntimeID == nil { next.defaultRuntimeID = runtime.id }
        return try await commit(next)
    }

    public func setDefaultRuntime(_ id: UUID) async throws -> AppConfiguration {
        guard configuration.runtimes.contains(where: { $0.id == id }) else { throw JerdError.invalid("Runtime record is missing.") }
        var next = configuration
        next.defaultRuntimeID = id
        return try await commit(next)
    }

    public func removeRuntime(_ id: UUID) async throws -> AppConfiguration {
        var next = configuration
        try next.removeRuntime(id)
        return try await commit(next)
    }

    public func setCaddy(_ caddy: CaddyRuntime) async throws -> AppConfiguration {
        var next = configuration
        next.caddy = caddy
        return try await commit(next)
    }

    private func commit(_ next: AppConfiguration) async throws -> AppConfiguration {
        guard loaded else { throw JerdError.corruptConfiguration("Load a valid configuration before making changes.") }
        guard !writing else { throw JerdError.invalid("A configuration operation is in progress. Retry the change.") }
        writing = true
        defer { writing = false }
        try await store.save(next)
        configuration = next
        return next
    }
}
