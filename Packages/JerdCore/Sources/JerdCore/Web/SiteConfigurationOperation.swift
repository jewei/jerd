import Foundation

public enum SiteConfigurationChange: Sendable {
    case save(Site, confirmed: Bool)
    case enabled(UUID, Bool)
    case remove(UUID)
    case defaultRuntime(UUID)
    case caddy(CaddyRuntime)
}

public struct PreparedSiteChange: Sendable {
    public let setup: HTTPSSetup
    let previous: AppConfiguration
    let candidate: AppConfiguration
    let startIfStopped: Bool
    let removedHostname: String?
}

public enum SiteChangeResult: Sendable {
    case committed(AppConfiguration)
    case needsApproval(PreparedSiteChange)
}

public protocol SiteEnvironmentOperating: Sendable {
    func runningConfiguration() async -> WebConfiguration?
    func systemStatus() async throws -> SystemSetupStatus
    func preflight(_ configuration: WebConfiguration) async throws -> PreparedWebConfiguration
    func ensure(_ configuration: WebConfiguration, prepared: PreparedWebConfiguration?) async throws
    func restoreRun(_ configuration: WebConfiguration) async throws
    func prepare(sites: [Site], caddy: CaddyRuntime) async throws -> HTTPSSetup
    func apply(_ setup: HTTPSSetup) async throws
    func removeHostname(_ hostname: String) async throws
    func restoreSystemStatus(_ status: SystemSetupStatus) async throws
    func requestStop() async
    func stop() async
}

public extension SiteEnvironmentOperating {
    func ensure(_ configuration: WebConfiguration) async throws { try await ensure(configuration, prepared: nil) }
}

/// One edit operation for the UI and tests: propose, prepare, approve if needed,
/// persist, activate. A failure restores both saved settings and the previous run.
public actor SiteConfigurationOperation {
    private let registry: SiteRegistry
    private let environment: any SiteEnvironmentOperating
    private var busy = false
    private var stopRequested = false
    public init(registry: SiteRegistry, environment: any SiteEnvironmentOperating) {
        self.registry = registry; self.environment = environment
    }

    public func apply(_ change: SiteConfigurationChange, startIfStopped: Bool = false) async throws -> SiteChangeResult {
        guard !busy else { throw JerdError.unavailable("Wait for the current site edit.") }
        busy = true; stopRequested = false; defer { busy = false }
        let previous = try await registry.snapshot()
        let candidate = try await registry.propose(change)
        let removed: String?
        if case .remove(let id) = change { removed = previous.sites.first { $0.id == id }?.hostname }
        else { removed = nil }
        return try await applyCandidate(candidate, previous: previous, startIfStopped: startIfStopped, removedHostname: removed)
    }

    public func approve(_ change: PreparedSiteChange) async throws -> AppConfiguration {
        guard !busy else { throw JerdError.unavailable("Wait for the current site edit.") }
        busy = true; stopRequested = false; defer { busy = false }
        guard try await registry.snapshot() == change.previous else { throw JerdError.unavailable("The site settings changed. Save and approve the edit again.") }
        let result = try await applyCandidate(change.candidate, previous: change.previous,
            startIfStopped: change.startIfStopped, removedHostname: change.removedHostname, approved: change.setup)
        guard case .committed(let configuration) = result else { throw JerdError.invalid("The approved site edit could not be applied.") }
        return configuration
    }

    public func requestStop() async { stopRequested = true; await environment.requestStop() }

    private func applyCandidate(_ candidate: AppConfiguration, previous: AppConfiguration, startIfStopped: Bool,
                                removedHostname: String?, approved: HTTPSSetup? = nil) async throws -> SiteChangeResult {
        if candidate == previous { return .committed(previous) }
        let running = await environment.runningConfiguration()
        let shouldRun = running != nil || startIfStopped
        let enabled = candidate.sites.filter(\.isEnabled)
        let plan = shouldRun && !enabled.isEmpty ? try WebConfiguration(candidate) : nil
        let status = try await environment.systemStatus()
        guard status.recovery == nil else { throw JerdError.unavailable("Recover the interrupted HTTPS setup in Advanced before changing sites.") }
        var prepared: PreparedWebConfiguration?
        if let plan {
            if running?.servesTheSameConfiguration(as: plan) != true { prepared = try await environment.preflight(plan) }
            let needsSetup = !status.hostsConfigured || !status.trustConfigured || status.trustPolicy != .serverTLS ||
                !Set(enabled.map(\.hostname)).isSubset(of: Set(status.hostnames))
            if needsSetup, approved == nil {
                let setup = try await environment.prepare(sites: enabled, caddy: plan.caddy)
                return .needsApproval(PreparedSiteChange(setup: setup, previous: previous, candidate: candidate,
                    startIfStopped: startIfStopped, removedHostname: removedHostname))
            }
        }
        try Task.checkCancellation()
        guard !stopRequested else { throw CancellationError() }
        var saved = false, changedSystem = false
        do {
            if let approved {
                guard Set(approved.request.hostnames) == Set(enabled.map(\.hostname)) else { throw JerdError.invalid("The approved hostnames do not match the edit.") }
                changedSystem = true
                try await environment.apply(approved)
            } else if let removedHostname, status.hostnames.contains(removedHostname) {
                changedSystem = true
                try await environment.removeHostname(removedHostname)
            }
            _ = try await registry.replace(candidate, expecting: previous)
            saved = true
            try Task.checkCancellation()
            guard !stopRequested else { throw CancellationError() }
            if let plan { try await environment.ensure(plan, prepared: prepared) }
            else if running != nil { await environment.stop() }
            return .committed(candidate)
        } catch {
            let failure = error.localizedDescription
            let saved = saved, changedSystem = changedSystem
            // Rollback must finish even when Stop cancelled preparation or startup.
            let recovery = await Task.detached { [self, registry, environment] in
                var failures = [String]()
                if saved {
                    do { _ = try await registry.replace(previous, expecting: candidate) }
                    catch { failures.append("Settings: \(error.localizedDescription)") }
                }
                if changedSystem {
                    do {
                        let current = try await environment.systemStatus()
                        guard current.recovery == nil else { throw JerdError.unavailable("HTTPS setup needs approved recovery in Advanced.") }
                        if current != status { try await environment.restoreSystemStatus(status) }
                    } catch { failures.append("HTTPS: \(error.localizedDescription)") }
                }
                if let running {
                    do { try await restoreUnlessStopped(running) }
                    catch { failures.append("Restart: \(error.localizedDescription)") }
                }
                return failures
            }.value
            if !recovery.isEmpty { throw JerdError.process("The site change failed: \(failure) Recovery needs attention. \(recovery.joined(separator: " "))") }
            if error is CancellationError { throw error }
            throw JerdError.process("The site change failed. The previous settings were restored. \(failure)")
        }
    }
    private func restoreUnlessStopped(_ configuration: WebConfiguration) async throws {
        guard !stopRequested else { return }
        do { try await environment.restoreRun(configuration) }
        catch is CancellationError { if !stopRequested { throw CancellationError() } }
    }

}
