import Foundation
import Testing
import Darwin
import Security
@testable import JerdCore

private final class MemoryTrust: CertificateTrustManaging, @unchecked Sendable {
    private let lock = NSLock()
    private struct Entry { let hostnames: [String]; let policy: CertificateTrustPolicy }
    private var entries: [Data: Entry] = [:]
    private var failInstall = false
    private var failRemoval = false
    private var interrupt = false
    func failNextInstall() { lock.withLock { failInstall = true } }
    func failNextRemoval() { lock.withLock { failRemoval = true } }
    func interruptNextInstall() { lock.withLock { interrupt = true } }
    func validate(_ der: Data, installationID: UUID) throws {}
    func isInstalled(_ der: Data, hostnames: [String], policy: CertificateTrustPolicy = .hostnames) throws -> Bool {
        lock.withLock { entries[der]?.policy == policy && (policy == .serverTLS || entries[der]?.hostnames == hostnames) }
    }
    func install(_ der: Data, hostnames: [String], policy: CertificateTrustPolicy = .hostnames, replacingOwned: Bool) throws {
        try lock.withLock {
            if interrupt { interrupt = false; throw JerdError.approvalInterrupted("Test app disconnect") }
            if failInstall { failInstall = false; throw JerdError.unavailable("Test trust failure") }
            entries[der] = Entry(hostnames: hostnames, policy: policy)
        }
    }
    func remove(_ der: Data) throws {
        try lock.withLock {
            entries[der] = nil
            if failRemoval { failRemoval = false; throw JerdError.unavailable("Test partial removal failure") }
        }
    }
}

struct SetupTransactionTests {
    @Test func serverTrustRequiresItsOwnApprovalAndUsesOnlySSLPolicy() throws {
        let der = Data("approved CA".utf8), hosts = ["games-hk.test", "games-jp.test"]
        let change = TrustConsentRequest(certificateDER: der, hostnames: hosts, policy: .serverTLS)
        let legacyApproval = TrustConsentScope(certificateDER: der, hostnames: Set(hosts), allowRemoval: true)
        #expect(!legacyApproval.allows(change))
        let approval = TrustConsentScope(certificateDER: der, hostnames: Set(hosts), allowRemoval: true, policies: [.serverTLS])
        #expect(approval.allows(change))
        #expect(!approval.allows(TrustConsentRequest(certificateDER: der, hostnames: ["other.test"], policy: .serverTLS)))
        #expect(!approval.allows(TrustConsentRequest(certificateDER: Data("another CA".utf8), hostnames: hosts, policy: .serverTLS)))
        let settings = try CertificateTrustSettings.make(policy: .serverTLS, hostnames: hosts)
        #expect(settings.count == 1)
        #expect(settings[0][kSecTrustSettingsPolicyString as String] == nil)
        #expect(CertificateTrustSettings.matches(settings, policy: .serverTLS, hostnames: hosts))
        #expect(!CertificateTrustSettings.matches(settings, policy: .hostnames, hostnames: hosts))
        let legacy = try CertificateTrustSettings.make(policy: .hostnames, hostnames: hosts)
        #expect(CertificateTrustSettings.matches(legacy, policy: .hostnames, hostnames: hosts))
        #expect(!CertificateTrustSettings.matches(legacy, policy: .serverTLS, hostnames: hosts))
        #expect(!CertificateTrustSettings.matches([[:]], policy: .serverTLS, hostnames: hosts))
        for otherPolicy in [SecPolicyCreateBasicX509(), SecPolicyCreateSSL(false, nil)] {
            var other = settings
            other[0][kSecTrustSettingsPolicy as String] = otherPolicy
            #expect(!CertificateTrustSettings.matches(other, policy: .serverTLS, hostnames: hosts))
        }
    }

    @Test(arguments: [1, 2])
    func legacyTrustUpgradePreservesApprovalAndRollback(version: Int) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("helper")
        try PrivateFiles.directory(directory)
        let original = Data("127.0.0.1 localhost\n".utf8)
        let hostsURL = root.appendingPathComponent("hosts")
        try HostsDocument.replacing(original, hostname: "old.test", expectedHostname: nil).write(to: hostsURL)
        let identity = UUID(), der = Data("test CA".utf8)
        var legacy: [String: Any] = ["schemaVersion": version, "ownerUID": getuid(), "installationID": identity.uuidString,
            "certificateDER": der.base64EncodedString()]
        if version == 1 { legacy["hostname"] = "old.test" } else { legacy["hostnames"] = ["old.test"] }
        let record = directory.appendingPathComponent("registration.json")
        let legacyBytes = try JSONSerialization.data(withJSONObject: legacy)
        try PrivateFiles.write(legacyBytes, to: record)
        let trust = MemoryTrust()
        try trust.install(der, hostnames: ["old.test"], replacingOwned: true)
        let store = PrivilegedSetupStore(directory: directory, expectedFileOwner: getuid(),
            hosts: AtomicHostsFile(url: hostsURL, expectedOwner: getuid()), certificates: trust)
        let before = try await store.status(ownerUID: getuid())
        #expect(before.trustConfigured && before.trustPolicy == .hostnames)
        let upgrade = SystemRegistrationRequest(installationID: identity, hostnames: ["old.test"], certificateDER: der, trustPolicy: .serverTLS)
        #expect(try Data(contentsOf: record) == legacyBytes)
        trust.failNextInstall()
        await #expect(throws: (any Error).self) { try await store.configure(upgrade, ownerUID: getuid()) }
        #expect(try await store.status(ownerUID: getuid()) == before)
        #expect(try Data(contentsOf: record) == legacyBytes)
        try await store.configure(upgrade, ownerUID: getuid())
        let approved = try await store.status(ownerUID: getuid())
        #expect(approved.trustConfigured && approved.trustPolicy == .serverTLS)
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: record)) as? [String: Any])
        #expect(saved["schemaVersion"] as? Int == 3)
        #expect(saved["trustPolicy"] as? String == "serverTLS")
        trust.failNextRemoval()
        await #expect(throws: (any Error).self) { try await store.remove(ownerUID: getuid()) }
        #expect(try await store.status(ownerUID: getuid()) == approved)
        try await store.remove(ownerUID: getuid())
        #expect(try Data(contentsOf: hostsURL) == original)
    }

    @Test func consentIsLimitedToApprovedCertificateAndHosts() {
        let der = Data("approved CA".utf8)
        let scope = TrustConsentScope(certificateDER: der, hostnames: ["old.test", "new.test"], allowRemoval: true)
        #expect(scope.allows(TrustConsentRequest(certificateDER: der, hostname: "old.test")))
        #expect(scope.allows(TrustConsentRequest(certificateDER: der, hostname: "new.test")))
        #expect(scope.allows(TrustConsentRequest(certificateDER: der, hostname: nil)))
        #expect(scope.allows(TrustConsentRequest(certificateDER: der, hostnames: ["old.test", "new.test"])))
        #expect(!scope.allows(TrustConsentRequest(certificateDER: der, hostnames: [])))
        #expect(!scope.allows(TrustConsentRequest(certificateDER: der, hostnames: ["new.test", "other.test"])))
        #expect(!scope.allows(TrustConsentRequest(certificateDER: der, hostname: "other.test")))
        #expect(!scope.allows(TrustConsentRequest(certificateDER: Data("other CA".utf8), hostname: "new.test")))
        #expect(!TrustConsentScope(certificateDER: der, hostnames: ["new.test"], allowRemoval: false)
            .allows(TrustConsentRequest(certificateDER: der, hostname: nil)))
    }

    @Test func upgradesSingleHostRecordAndRollsBackMultipleHostChange() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("helper")
        try PrivateFiles.directory(directory)
        let original = Data("127.0.0.1 localhost\n".utf8)
        let hostsURL = root.appendingPathComponent("hosts")
        try HostsDocument.replacing(original, hostname: "old.test", expectedHostname: nil).write(to: hostsURL)
        let identity = UUID(), der = Data("test CA".utf8)
        let legacy: [String: Any] = ["schemaVersion": 1, "ownerUID": getuid(), "installationID": identity.uuidString,
            "hostname": "old.test", "certificateDER": der.base64EncodedString()]
        try PrivateFiles.write(JSONSerialization.data(withJSONObject: legacy), to: directory.appendingPathComponent("registration.json"))
        let trust = MemoryTrust()
        try trust.install(der, hostnames: ["old.test"], replacingOwned: true)
        let store = PrivilegedSetupStore(directory: directory, expectedFileOwner: getuid(),
            hosts: AtomicHostsFile(url: hostsURL, expectedOwner: getuid()), certificates: trust)
        #expect(try await store.status(ownerUID: getuid()).hostnames == ["old.test"])
        let request = SystemRegistrationRequest(installationID: identity, hostnames: ["old.test", "new.test"], certificateDER: der)
        try await store.configure(request, ownerUID: getuid())
        let snapshot = try await store.status(ownerUID: getuid())
        #expect(snapshot.hostnames == ["new.test", "old.test"])
        #expect(snapshot.hostsConfigured && snapshot.trustConfigured)
        trust.failNextInstall()
        await #expect(throws: (any Error).self) {
            try await store.configure(SystemRegistrationRequest(installationID: identity, hostnames: ["other.test"], certificateDER: der), ownerUID: getuid())
        }
        #expect(try await store.status(ownerUID: getuid()) == snapshot)
        try await store.remove(ownerUID: getuid())
        #expect(try Data(contentsOf: hostsURL) == original)
    }

    @Test func interruptedConsentRetainsRecoveryEvidence() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("hosts")
        let original = Data("127.0.0.1 localhost\n".utf8)
        try original.write(to: url)
        let trust = MemoryTrust()
        let directory = root.appendingPathComponent("helper")
        let store = PrivilegedSetupStore(directory: directory, expectedFileOwner: getuid(),
            hosts: AtomicHostsFile(url: url, expectedOwner: getuid()), certificates: trust)
        trust.interruptNextInstall()
        await #expect(throws: (any Error).self) {
            try await store.configure(SystemRegistrationRequest(installationID: UUID(), hostname: "demo.test", certificateDER: Data("CA".utf8)), ownerUID: getuid())
        }
        #expect(try Data(contentsOf: url) == original)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending.json").path))
        await #expect(throws: (any Error).self) { try await store.status(ownerUID: getuid()) }
    }

    @Test func setupRollbackOwnerAndRemoval() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let hostsURL = root.appendingPathComponent("hosts")
        let original = Data("127.0.0.1 localhost\n10.0.0.1 unrelated.test\n".utf8)
        try original.write(to: hostsURL)
        let hosts = AtomicHostsFile(url: hostsURL, expectedOwner: getuid())
        let certificates = MemoryTrust()
        let store = PrivilegedSetupStore(directory: root.appendingPathComponent("helper"), expectedFileOwner: getuid(),
                                         hosts: hosts, certificates: certificates)
        let identity = UUID()
        let der = Data("test CA".utf8)
        let request = SystemRegistrationRequest(installationID: identity, hostname: "demo.test", certificateDER: der)
        certificates.failNextInstall()
        await #expect(throws: (any Error).self) { try await store.configure(request, ownerUID: getuid()) }
        #expect(try hosts.read() == original)
        #expect(try await store.status(ownerUID: getuid()).hostname == nil)
        try await store.configure(request, ownerUID: getuid())
        #expect(try await store.status(ownerUID: getuid()).trustConfigured)
        await #expect(throws: (any Error).self) { try await store.remove(ownerUID: getuid() + 1) }
        await #expect(throws: (any Error).self) {
            try await store.configure(SystemRegistrationRequest(installationID: UUID(), hostname: "demo.test", certificateDER: der), ownerUID: getuid())
        }
        certificates.failNextInstall()
        await #expect(throws: (any Error).self) {
            try await store.configure(SystemRegistrationRequest(installationID: identity, hostname: "shop.test", certificateDER: der), ownerUID: getuid())
        }
        #expect(try await store.status(ownerUID: getuid()).hostname == "demo.test")
        #expect(try await store.status(ownerUID: getuid()).trustConfigured)
        try await store.configure(SystemRegistrationRequest(installationID: identity, hostname: "shop.test", certificateDER: der), ownerUID: getuid())
        #expect(try await store.status(ownerUID: getuid()).hostname == "shop.test")
        certificates.failNextRemoval()
        await #expect(throws: (any Error).self) { try await store.remove(ownerUID: getuid()) }
        #expect(try await store.status(ownerUID: getuid()).trustConfigured)
        #expect(try await store.status(ownerUID: getuid()).hostsConfigured)
        try await store.remove(ownerUID: getuid())
        #expect(try hosts.read() == original)
        #expect(try await store.status(ownerUID: getuid()).hostname == nil)
        #expect(try !certificates.isInstalled(der, hostname: "shop.test"))
    }

    @Test func preservesInterruptedSetup() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("pending".utf8).write(to: root.appendingPathComponent("pending.json"))
        let hosts = root.appendingPathComponent("hosts")
        try Data("keep".utf8).write(to: hosts)
        let store = PrivilegedSetupStore(directory: root, expectedFileOwner: getuid(),
            hosts: AtomicHostsFile(url: hosts, expectedOwner: getuid()), certificates: MemoryTrust())
        await #expect(throws: (any Error).self) { try await store.remove(ownerUID: getuid()) }
        #expect(try String(contentsOf: hosts, encoding: .utf8) == "keep")
        #expect(try String(contentsOf: root.appendingPathComponent("pending.json"), encoding: .utf8) == "pending")
    }

    @Test(arguments: ["My Folder", "café", "项目", "---", String(repeating: "x", count: 90)])
    func suggestedHostnameIsValid(_ folder: String) throws {
        #expect(try Hostname.validate(Hostname.suggestion(folderName: folder)) == Hostname.suggestion(folderName: folder))
        #expect(Hostname.suggestion(folderName: "My Folder") == "my-folder.test")
    }
}

private actor FakeSystem: SystemIntegrating {
    var snapshot: SystemSetupStatus
    var acquired = 0
    var released = 0
    init(_ snapshot: SystemSetupStatus) { self.snapshot = snapshot }
    func status() -> SystemSetupStatus { snapshot }
    func configure(_ request: SystemRegistrationRequest) {
        snapshot = SystemSetupStatus(hostnames: request.hostnames, installationID: request.installationID,
            certificateSHA256: InstallationCertificate.fingerprint(request.certificateDER), certificateDER: request.certificateDER,
            hostsConfigured: true, trustConfigured: true, trustPolicy: request.trustPolicy)
    }
    func acquireListeners() throws -> ListeningSockets {
        acquired += 1
        return try ListeningSockets.bind(httpPort: 0, httpsPort: 0)
    }
    func releaseListeners() { released += 1 }
    func removeSetup() { snapshot = SystemSetupStatus() }
}

private actor FakeEngine: EngineServing {
    var state: EnvironmentState = .stopped
    var starts = 0
    var startedSiteIDs: Set<UUID> = []
    func start(sites: [SiteRuntime], caddy: CaddyRuntime, paths: EnginePaths,
               httpsPort: UInt16, httpPort: UInt16, listeningSockets: ListeningSockets?) {
        starts += 1
        startedSiteIDs = Set(sites.map { $0.site.id })
        state = .running
    }
    func stop() { state = .stopped }
    func crash() { state = .failed("test exit") }
}

private actor RecordingProbe: TrustProbing {
    var checked: [String] = []
    func check(hostname: String) { checked.append(hostname) }
}

private struct FakeProbe: TrustProbing {
    var fail = false
    func check(hostname: String) throws {
        if fail { throw JerdError.unavailable("System trust test failed") }
    }
}

struct EnvironmentTests {
    @Test(arguments: [false, true], [CertificateTrustPolicy.hostnames, .serverTLS])
    func allSitesNeedApprovalAndEachHostnameIsChecked(approved: Bool, policy: CertificateTrustPolicy) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = UUID(), der = Data("test CA".utf8)
        try Data(identity.uuidString.utf8).write(to: root.appendingPathComponent("installation-id"))
        let caDir = root.appendingPathComponent("certificates/pki/authorities/jerd")
        try PrivateFiles.directory(caDir)
        try Data("-----BEGIN CERTIFICATE-----\n\(der.base64EncodedString())\n-----END CERTIFICATE-----".utf8)
            .write(to: caDir.appendingPathComponent("root.crt"))
        let hosts = approved ? ["one.test", "two.test"] : ["one.test"]
        let system = FakeSystem(SystemSetupStatus(hostnames: hosts, installationID: identity,
            certificateSHA256: InstallationCertificate.fingerprint(der), certificateDER: der, hostsConfigured: true,
            trustConfigured: true, trustPolicy: policy))
        let engine = FakeEngine(), probe = RecordingProbe()
        let environment = LocalEnvironment(directory: root, system: system, engine: engine, probe: probe)
        let runtime = sampleRuntime()
        let one = makeSite(root, hostname: "one.test"), two = makeSite(root, hostname: "two.test")
        let selections = [SiteRuntime(site: one, runtime: runtime), SiteRuntime(site: two, runtime: runtime)]
        let caddy = CaddyRuntime(path: "/unused", version: "v2.11.4", architectures: [.arm64])
        if approved && policy == .serverTLS {
            try await environment.start(sites: selections, caddy: caddy)
            #expect(await engine.startedSiteIDs == [one.id, two.id])
            #expect(await probe.checked == ["one.test", "two.test"])
            try await environment.removeHostname("one.test")
            #expect(try await system.status().hostnames == ["two.test"])
            #expect(try await system.status().trustPolicy == .serverTLS)
            try await environment.start(sites: [selections[1]], caddy: caddy)
            #expect(await engine.startedSiteIDs == [two.id])
            await environment.stop()
        } else {
            await #expect(throws: JerdError.self) { try await environment.start(sites: selections, caddy: caddy) }
            #expect(await engine.starts == 0)
            #expect(await system.acquired == 0)
        }
    }

    @Test(arguments: [false, true])
    func trustFailureStopsServicesAndSuccessMonitorsExit(_ fail: Bool) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = UUID()
        try Data(identity.uuidString.utf8).write(to: root.appendingPathComponent("installation-id"))
        let caDir = root.appendingPathComponent("certificates/pki/authorities/jerd")
        try PrivateFiles.directory(caDir)
        let der = Data("test CA".utf8)
        try Data("-----BEGIN CERTIFICATE-----\n\(der.base64EncodedString())\n-----END CERTIFICATE-----".utf8)
            .write(to: caDir.appendingPathComponent("root.crt"))
        let system = FakeSystem(SystemSetupStatus(hostname: "demo.test", installationID: identity,
            certificateSHA256: InstallationCertificate.fingerprint(der), hostsConfigured: true, trustConfigured: true, trustPolicy: .serverTLS))
        let engine = FakeEngine()
        let environment = LocalEnvironment(directory: root, system: system, engine: engine, probe: FakeProbe(fail: fail))
        let site = Site(displayName: "Demo", projectPath: root.path, documentRoot: root.path, hostname: "demo.test")
        let runtime = DevelopmentRuntime(cliPath: "/unused", fpmPath: "/unused", version: "8.5.11", architectures: [.arm64], cliExtensions: [], fpmExtensions: [])
        let caddy = CaddyRuntime(path: "/unused", version: "v2.11.4", architectures: [.arm64])
        if fail {
            await #expect(throws: (any Error).self) { try await environment.start(site: site, runtime: runtime, caddy: caddy) }
            #expect(await engine.state == .stopped)
        } else {
            try await environment.start(site: site, runtime: runtime, caddy: caddy)
            #expect(await environment.state == .running)
            await engine.crash()
            let deadline = ContinuousClock.now + .seconds(3)
            while await environment.state == .running, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(await environment.state == .failed("test exit"))
        }
        #expect(await system.acquired == 1)
        #expect(await system.released == 1)
        await environment.stop()
    }

    @Test func missingSetupDoesNotStartAnyProcess() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let system = FakeSystem(SystemSetupStatus())
        let engine = FakeEngine()
        let environment = LocalEnvironment(directory: root, system: system, engine: engine, probe: FakeProbe())
        let site = Site(displayName: "Demo", projectPath: root.path, documentRoot: root.path, hostname: "demo.test")
        let runtime = DevelopmentRuntime(cliPath: "/unused", fpmPath: "/unused", version: "8.5.11", architectures: [.arm64], cliExtensions: [], fpmExtensions: [])
        await #expect(throws: (any Error).self) {
            try await environment.start(site: site, runtime: runtime, caddy: CaddyRuntime(path: "/unused", version: "v2.11.4", architectures: [.arm64]))
        }
        #expect(await engine.starts == 0)
        #expect(await system.acquired == 0)
    }
}
