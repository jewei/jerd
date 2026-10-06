import Foundation
import JerdFoundation

@testable import JerdWeb

/// An in-memory setup gateway. Every change halts the fake coordinator, like the real one.
actor FakeGateway: SystemSetupManaging {
    private(set) var current: HTTPSSetupStatus
    private(set) var prepared: [[String]] = []
    private(set) var applications = 0
    private(set) var restores = 0
    private(set) var isRestoring = false
    private var failRestore = false
    private var holdRestore = false
    private var waiter: CheckedContinuation<Void, Never>?
    /// This installation's CA. The default is the fixture CA, which `FakeSystem.approved` names.
    private var authority: InstallationAuthority?
    let coordinator: FakeCoordinator

    init(_ status: HTTPSSetupStatus, coordinator: FakeCoordinator) {
        current = status
        self.coordinator = coordinator
        authority = InstallationAuthority(
            installationID: Certificates.installationID, fingerprint: (try? Certificates.authority().fingerprint) ?? "")
    }

    func set(_ status: HTTPSSetupStatus) { current = status }
    func setLocalAuthority(_ authority: InstallationAuthority?) { self.authority = authority }
    func localAuthority() -> InstallationAuthority? { authority }
    func failNextRestore() { failRestore = true }
    func holdNextRestore() { holdRestore = true }

    func resume() {
        waiter?.resume()
        waiter = nil
    }

    func status() -> HTTPSSetupStatus { current }

    func prepare(hostnames: [String], caddy: CaddyRuntime) throws -> HTTPSSetup {
        prepared.append(hostnames)
        let validated = try HostnamePolicy.validateSet(hostnames).map(\.value)
        return HTTPSSetup(
            registration: HTTPSRegistration(
                installationID: Certificates.installationID, hostnames: validated,
                certificateDER: try Certificates.authority().der, trustPolicy: .serverTLS))
    }

    func apply(_ setup: HTTPSSetup) async {
        applications += 1
        await coordinator.halt()
        current.hostnames = setup.hostnames
        current.hostsConfigured = true
        current.trustConfigured = true
        current.trustPolicy = .serverTLS
    }

    func removeHostnames(_ hostnames: Set<String>) async {
        await coordinator.halt()
        current.hostnames.removeAll { hostnames.contains($0) }
    }

    func restore(_ status: HTTPSSetupStatus) async throws {
        restores += 1
        isRestoring = true
        if holdRestore {
            holdRestore = false
            await withCheckedContinuation { waiter = $0 }
        }
        isRestoring = false
        await coordinator.halt()
        if failRestore {
            failRestore = false
            throw JerdError.unavailable("Test restore failure")
        }
        current = status
    }

    func removeSetup() async {
        await coordinator.halt()
        current = HTTPSSetupStatus()
    }
}

/// A transaction over a fake store, coordinator, and gateway, with real project folders.
struct TransactionHarness {
    let folder: TemporaryDirectory
    let store: FakeConfigurationStore
    let registry: SiteRegistry
    let coordinator: FakeCoordinator
    let gateway: FakeGateway
    let transaction: SiteChangeTransaction
    let before: AppConfiguration

    /// `running` lists the hostnames of `sites` that run; `approved` the approved hostnames.
    init(sites hostnames: [String] = ["demo.test"], running: [String]? = nil, approved: [String]? = nil) async throws {
        folder = try TemporaryDirectory(" transaction")
        let validator = SiteValidator()
        var sites: [Site] = []
        for host in hostnames {
            sites.append(
                try validator.validate(
                    Samples.site(try folder.folder("projects/\(host)"), hostname: host), existing: sites,
                    documentRootConfirmed: true))
        }
        before = Samples.configuration(sites)
        store = FakeConfigurationStore(before)
        registry = SiteRegistry(store: store)
        _ = try await registry.load()
        let runningIDs = Set(sites.filter { (running ?? hostnames).contains($0.hostname) }.map(\.id))
        coordinator = FakeCoordinator(runningIDs.isEmpty ? nil : try ServingPlan(before, siteIDs: runningIDs))
        gateway = FakeGateway(try FakeSystem.approved(approved ?? hostnames), coordinator: coordinator)
        transaction = SiteChangeTransaction(
            registry: registry, reducer: SiteChangeReducer(hosts: FakeHostsFile()), coordinator: coordinator,
            gateway: gateway)
    }

    func site(_ hostname: String) -> Site { before.sites.first { $0.hostname == hostname }! }

    func runningIDs() async -> Set<UUID>? { await coordinator.running?.siteIDs }

    func remove() { folder.remove() }
}
