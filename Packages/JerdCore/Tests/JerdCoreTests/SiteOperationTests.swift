import Foundation
import Testing
@testable import JerdCore

private actor OperationStore: ConfigurationStore {
    var configuration: AppConfiguration
    var failNextSave = false
    init(_ configuration: AppConfiguration) { self.configuration = configuration }
    func load() -> AppConfiguration { configuration }
    func rejectNextSave() { failNextSave = true }
    func save(_ next: AppConfiguration) throws {
        if failNextSave { failNextSave = false; throw JerdError.unavailable("Test save failure") }
        configuration = next
    }
}

private actor OperationEnvironment: SiteEnvironmentOperating {
    var running: WebConfiguration?
    var status: SystemSetupStatus
    var preflights = 0, stops = 0, launches = 0, applications = 0
    var failPreflight = false, failActivation = false, failRestore = false, delayPreflight = false
    var stopped = false
    var restoringSystem = false
    var restoreWaiter: CheckedContinuation<Void, Never>?
    var suspendSystemRestore = false
    func suspendRestore() { suspendSystemRestore = true }
    func resumeRestore() { restoreWaiter?.resume(); restoreWaiter = nil }
    init(_ plan: WebConfiguration) {
        running = plan
        status = SystemSetupStatus(hostnames: plan.sites.map { $0.site.hostname }, installationID: UUID(),
            certificateDER: Data("test CA".utf8), hostsConfigured: true, trustConfigured: true, trustPolicy: .serverTLS)
    }
    func failures(preflight: Bool = false, activation: Bool = false, restore: Bool = false, delay: Bool = false) {
        failPreflight = preflight; failActivation = activation; failRestore = restore; delayPreflight = delay
    }
    func runningConfiguration() -> WebConfiguration? { running }
    func systemStatus() -> SystemSetupStatus { status }
    func preflight(_ configuration: WebConfiguration) async throws -> PreparedWebConfiguration {
        preflights += 1
        if delayPreflight { try await Task.sleep(for: .seconds(20)) }
        if failPreflight { throw JerdError.invalid("Test invalid runtime") }
        return PreparedWebConfiguration(id: UUID(), environmentID: UUID(), configuration: configuration, stamps: [:])
    }
    func ensure(_ configuration: WebConfiguration, prepared: PreparedWebConfiguration? = nil) throws {
        if running?.servesTheSameConfiguration(as: configuration) == true { return }
        launches += 1
        if failActivation { failActivation = false; running = nil; throw JerdError.process("Test failed launch") }
        if failRestore { throw JerdError.process("Test failed restore") }
        running = configuration
    }
    func prepare(sites: [Site], caddy: CaddyRuntime) -> HTTPSSetup {
        HTTPSSetup(sites: sites, request: SystemRegistrationRequest(installationID: status.installationID!,
            hostnames: sites.map(\.hostname), certificateDER: status.certificateDER!, trustPolicy: .serverTLS))
    }
    func apply(_ setup: HTTPSSetup) { applications += 1; status.hostnames = setup.request.hostnames; running = nil }
    func removeHostname(_ hostname: String) { status.hostnames.removeAll { $0 == hostname }; running = nil }
    func restoreRun(_ configuration: WebConfiguration) throws {
        guard !stopped else { throw CancellationError() }
        try ensure(configuration)
    }
    func restoreSystemStatus(_ snapshot: SystemSetupStatus) async {
        restoringSystem = true
        if suspendSystemRestore { await withCheckedContinuation { restoreWaiter = $0 } }
        status = snapshot
    }
    func requestStop() { stopped = true }
    func stop() { stops += 1; running = nil }
}

struct SiteOperationTests {
    private func fixture(_ root: URL) throws -> AppConfiguration {
        let runtime = sampleRuntime()
        var configuration = AppConfiguration()
        configuration.runtimes = [runtime]; configuration.defaultRuntimeID = runtime.id
        configuration.caddy = CaddyRuntime(path: "/unused-caddy", version: "2.11.4", architectures: [.current])
        configuration.sites = [try SiteValidator().validate(makeSite(root), existing: [], documentRootConfirmed: true)]
        return configuration
    }

    @Test(arguments: [false, true])
    func invalidEditsAndRuntimePreparationKeepThePreviousRun(runtimeFailure: Bool) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try fixture(root), store = OperationStore(before)
        let registry = SiteRegistry(store: store)
        _ = try await registry.load()
        let environment = OperationEnvironment(try WebConfiguration(before))
        await environment.failures(preflight: runtimeFailure)
        let operation = SiteConfigurationOperation(registry: registry, environment: environment)
        var site = before.sites[0]
        if runtimeFailure { site.hostname = "changed.test" } else { site.documentRoot = "/missing" }
        await #expect(throws: (any Error).self) { try await operation.apply(.save(site, confirmed: true)) }
        #expect(try await registry.snapshot() == before)
        #expect(await environment.runningConfiguration()?.sites[0].site == before.sites[0])
        #expect(await environment.stops == 0)
        #expect(await environment.launches == 0)
    }

    @Test(arguments: [false, true])
    func approvedChangesRestoreSettingsAndRunAfterActivationOrSaveFailure(saveFailure: Bool) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try fixture(root), store = OperationStore(before)
        let registry = SiteRegistry(store: store)
        _ = try await registry.load()
        let environment = OperationEnvironment(try WebConfiguration(before))
        let operation = SiteConfigurationOperation(registry: registry, environment: environment)
        var site = before.sites[0]; site.hostname = "changed.test"
        let result = try await operation.apply(.save(site, confirmed: true))
        guard case .needsApproval(let pending) = result else { Issue.record("Expected approval before persistence"); return }
        #expect(try await registry.snapshot() == before)
        #expect(await environment.launches == 0)
        #expect(await environment.applications == 0)
        if saveFailure { await store.rejectNextSave() } else { await environment.failures(activation: true) }
        await #expect(throws: (any Error).self) { try await operation.approve(pending) }
        #expect(try await registry.snapshot() == before)
        #expect(await environment.systemStatus().hostnames == [before.sites[0].hostname])
        #expect(await environment.runningConfiguration()?.sites[0].site == before.sites[0])
    }

    @Test func rollbackFailureIsReported() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try fixture(root), store = OperationStore(before)
        let registry = SiteRegistry(store: store)
        _ = try await registry.load()
        let environment = OperationEnvironment(try WebConfiguration(before))
        await environment.failures(activation: true, restore: true)
        let operation = SiteConfigurationOperation(registry: registry, environment: environment)
        let caddy = CaddyRuntime(path: "/changed-caddy", version: before.caddy!.version, architectures: [.current])
        do { _ = try await operation.apply(.caddy(caddy)); Issue.record("Expected failed activation") }
        catch { #expect(error.localizedDescription.contains("Recovery needs attention")) }
        #expect(try await registry.snapshot() == before)
        #expect(await environment.runningConfiguration() == nil)
    }

    @Test func displayNameEditKeepsTheEffectiveRunAndApprovalRejectsStaleSettings() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try fixture(root), store = OperationStore(before)
        let registry = SiteRegistry(store: store)
        _ = try await registry.load()
        let environment = OperationEnvironment(try WebConfiguration(before))
        let operation = SiteConfigurationOperation(registry: registry, environment: environment)
        var renamed = before.sites[0]; renamed.displayName = "Renamed"
        _ = try await operation.apply(.save(renamed, confirmed: true))
        #expect(await environment.preflights == 0)
        #expect(await environment.launches == 0)
        #expect(await environment.stops == 0)
        #expect(try await registry.snapshot().sites[0].displayName == "Renamed")
        renamed.hostname = "changed.test"
        guard case .needsApproval(let pending) = try await operation.apply(.save(renamed, confirmed: true)) else {
            Issue.record("Expected approval"); return
        }
        _ = try await registry.setEnabled(renamed.id, enabled: false)
        await #expect(throws: (any Error).self) { try await operation.approve(pending) }
        #expect(await environment.applications == 0)
    }

    @Test func stopDuringSystemRollbackDoesNotRestartThePreviousRun() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try fixture(root), store = OperationStore(before)
        let registry = SiteRegistry(store: store)
        _ = try await registry.load()
        let environment = OperationEnvironment(try WebConfiguration(before))
        let operation = SiteConfigurationOperation(registry: registry, environment: environment)
        var site = before.sites[0]; site.hostname = "changed.test"
        guard case .needsApproval(let pending) = try await operation.apply(.save(site, confirmed: true)) else {
            Issue.record("Expected approval"); return
        }
        await environment.failures(activation: true)
        await environment.suspendRestore()
        let task = Task { try await operation.approve(pending) }
        while await !environment.restoringSystem { await Task.yield() }
        await operation.requestStop()
        await environment.resumeRestore()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(try await registry.snapshot() == before)
        #expect(await environment.systemStatus().hostnames == [before.sites[0].hostname])
        #expect(await environment.launches == 1)
        #expect(await environment.runningConfiguration() == nil)
    }

    @Test func stopCancelsPreparationWithoutCommittingOrRestarting() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let before = try fixture(root), store = OperationStore(before)
        let registry = SiteRegistry(store: store)
        _ = try await registry.load()
        let environment = OperationEnvironment(try WebConfiguration(before))
        await environment.failures(delay: true)
        let operation = SiteConfigurationOperation(registry: registry, environment: environment)
        let caddy = CaddyRuntime(path: "/changed-caddy", version: before.caddy!.version, architectures: [.current])
        let change = SiteConfigurationChange.caddy(caddy)
        let task = Task { try await operation.apply(change) }
        while await environment.preflights == 0 { await Task.yield() }
        await operation.requestStop(); task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        await environment.stop()
        #expect(try await registry.snapshot() == before)
        #expect(await environment.launches == 0)
        #expect(await environment.runningConfiguration() == nil)
    }
}
