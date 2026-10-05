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
    private var partiallyFailInstall = false
    private var failRemoval = false
    private var interrupt = false
    func failNextInstall() { lock.withLock { failInstall = true } }
    func partiallyFailNextInstall() { lock.withLock { partiallyFailInstall = true } }
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
            if partiallyFailInstall {
                partiallyFailInstall = false
                throw JerdError.partialChange("Test partial trust failure")
            }
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
    @Test(arguments: [false, true])
    func hostsRestorationFailureRetainsSetupJournal(removing: Bool) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("hosts")
        let directory = root.appendingPathComponent("helper")
        let original = Data("127.0.0.1 localhost\n".utf8)
        try original.write(to: url)
        let trust = MemoryTrust()
        let request = SystemRegistrationRequest(installationID: UUID(), hostname: "demo.test", certificateDER: Data("test CA".utf8))
        if removing {
            let initial = PrivilegedSetupStore(directory: directory, expectedFileOwner: getuid(),
                hosts: AtomicHostsFile(url: url, expectedOwner: getuid()), certificates: trust)
            try await initial.configure(request, ownerUID: getuid())
        }
        let before = try Data(contentsOf: url)
        let raced = before + Data("127.0.0.1 raced.test\n".utf8)
        let hosts = AtomicHostsFile(url: url, expectedOwner: getuid(), preExchange: {
            try raced.write(to: url, options: .atomic)
        }, preRestore: {
            throw JerdError.unavailable("Injected restoration failure")
        })
        let store = PrivilegedSetupStore(directory: directory, expectedFileOwner: getuid(), hosts: hosts, certificates: trust)
        await #expect(throws: (any Error).self) {
            if removing { try await store.remove(ownerUID: getuid()) }
            else { try await store.configure(request, ownerUID: getuid()) }
        }
        #expect(PrivateFiles.exists(directory.appendingPathComponent("pending.json")))
        #expect(try Data(contentsOf: directory.appendingPathComponent("hosts.previous")) == before)
        let recovery = try #require(await store.status(ownerUID: getuid()).recovery)
        #expect(recovery.phase.contains("Host replacement needs recovery"))
        let retained = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".jerd-hosts-") }
        #expect(retained.count == 1)
        #expect(try Data(contentsOf: #require(retained.first)) == raced)
        #expect(try trust.isInstalled(request.certificateDER, hostname: "demo.test") == removing)
    }

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
        var stored = settings
        stored[0]["kSecTrustSettingsPolicyName"] = "sslServer"
        #expect(CertificateTrustSettings.matches(stored, policy: .serverTLS, hostnames: hosts))
        for name in ["sslClient", "basicX509", ""] {
            stored[0]["kSecTrustSettingsPolicyName"] = name
            #expect(!CertificateTrustSettings.matches(stored, policy: .serverTLS, hostnames: hosts))
        }
        for extraKey in [kSecTrustSettingsAllowedError as String, "UnexpectedTrustSetting"] {
            var widened = settings
            widened[0][extraKey] = NSNumber(value: 1)
            #expect(!CertificateTrustSettings.matches(widened, policy: .serverTLS, hostnames: hosts))
        }
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
        let recovery = try #require(await store.status(ownerUID: getuid()).recovery)
        #expect(recovery.canRestore && recovery.canRemove)
        #expect(recovery.phase.contains("unknown"))
        try await store.recover(SystemRecoveryApproval(recordID: recovery.id, action: .restorePrevious), ownerUID: getuid())
        #expect(try await store.status(ownerUID: getuid()).recovery == nil)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func failedTrustCleanupRetainsRecoveryRecord() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let hostsURL = root.appendingPathComponent("hosts")
        let original = Data("127.0.0.1 localhost\n".utf8)
        try original.write(to: hostsURL)
        let trust = MemoryTrust()
        let directory = root.appendingPathComponent("helper")
        let store = PrivilegedSetupStore(directory: directory, expectedFileOwner: getuid(),
            hosts: AtomicHostsFile(url: hostsURL, expectedOwner: getuid()), certificates: trust)
        trust.partiallyFailNextInstall()
        trust.failNextRemoval()
        await #expect(throws: (any Error).self) {
            try await store.configure(SystemRegistrationRequest(installationID: UUID(), hostname: "demo.test",
                certificateDER: Data("CA".utf8)), ownerUID: getuid())
        }
        #expect(try Data(contentsOf: hostsURL) == original)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending.json").path))
    }

    @Test(arguments: ["prepared", "hosts", "trust", "registration"])
    func interruptedSetupRecoveryPreservesExternalHostEdits(stage: String) async throws {
        let root = try temporaryDirectory(" helper recovery")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("helper")
        try PrivateFiles.directory(directory)
        let original = Data("127.0.0.1 localhost\n".utf8)
        let hostsURL = root.appendingPathComponent("hosts")
        let identity = UUID(), der = Data("CA".utf8)
        let record: [String: Any] = ["schemaVersion": 3, "ownerUID": getuid(), "installationID": identity.uuidString,
            "hostnames": ["demo.test"], "certificateDER": der.base64EncodedString(), "trustPolicy": "serverTLS"]
        let journal: [String: Any] = ["schemaVersion": 1, "operation": "Configure HTTPS", "intended": record,
            "hostsSHA256": InstallationCertificate.fingerprint(original), "phase": stage]
        try PrivateFiles.write(JSONSerialization.data(withJSONObject: journal), to: directory.appendingPathComponent("pending.json"))
        try PrivateFiles.write(original, to: directory.appendingPathComponent("hosts.previous"))
        let changed = stage == "prepared" ? original : try HostsDocument.replacing(original, hostnames: ["demo.test"], expectedHostnames: [])
        let external = Data("10.0.0.1 another.test\n".utf8)
        try (changed + external).write(to: hostsURL)
        let trust = MemoryTrust()
        if stage == "trust" || stage == "registration" { try trust.install(der, hostnames: ["demo.test"], policy: .serverTLS, replacingOwned: false) }
        if stage == "registration" { try PrivateFiles.write(JSONSerialization.data(withJSONObject: record), to: directory.appendingPathComponent("registration.json")) }
        let store = PrivilegedSetupStore(directory: directory, expectedFileOwner: getuid(),
            hosts: AtomicHostsFile(url: hostsURL, expectedOwner: getuid()), certificates: trust)
        let report = try #require(await store.status(ownerUID: getuid()).recovery)
        #expect(report.canRestore)
        await #expect(throws: (any Error).self) {
            try await store.recover(.init(recordID: "stale approval", action: .restorePrevious), ownerUID: getuid())
        }
        try await store.recover(.init(recordID: report.id, action: .restorePrevious), ownerUID: getuid())
        #expect(try Data(contentsOf: hostsURL) == original + external)
        #expect(try await store.status(ownerUID: getuid()).hostnames.isEmpty)
        #expect(try !trust.isInstalled(der, hostnames: ["demo.test"], policy: .serverTLS))
    }

    @Test(arguments: ["prepared", "hosts", "trust", "registration"], [SystemRecoveryAction.restorePrevious, .removeSetup])
    func interruptedRemovalCanRestoreOrFinishWithoutReplacingExternalHosts(stage: String, action: SystemRecoveryAction) async throws {
        let root = try temporaryDirectory(" removal recovery")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("helper")
        try PrivateFiles.directory(directory)
        let plain = Data("127.0.0.1 localhost\n".utf8), external = Data("10.0.0.9 outside.test\n".utf8)
        let original = try HostsDocument.replacing(plain, hostnames: ["demo.test"], expectedHostnames: [])
        let hostsURL = root.appendingPathComponent("hosts")
        let identity = UUID(), der = Data("CA".utf8)
        let record: [String: Any] = ["schemaVersion": 3, "ownerUID": getuid(), "installationID": identity.uuidString,
            "hostnames": ["demo.test"], "certificateDER": der.base64EncodedString(), "trustPolicy": "serverTLS"]
        let previousBytes = try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted])
        let journal: [String: Any] = ["schemaVersion": 1, "operation": "Remove HTTPS", "previous": record,
            "previousBytes": previousBytes.base64EncodedString(), "hostsSHA256": InstallationCertificate.fingerprint(original), "phase": stage]
        try PrivateFiles.write(JSONSerialization.data(withJSONObject: journal), to: directory.appendingPathComponent("pending.json"))
        try PrivateFiles.write(original, to: directory.appendingPathComponent("hosts.previous"))
        try ((stage == "prepared" ? original : plain) + external).write(to: hostsURL)
        let trust = MemoryTrust()
        if stage == "prepared" || stage == "hosts" { try trust.install(der, hostnames: ["demo.test"], policy: .serverTLS, replacingOwned: false) }
        let registration = directory.appendingPathComponent("registration.json")
        if stage != "registration" { try PrivateFiles.write(previousBytes, to: registration) }
        let store = PrivilegedSetupStore(directory: directory, expectedFileOwner: getuid(),
            hosts: AtomicHostsFile(url: hostsURL, expectedOwner: getuid()), certificates: trust)
        let report = try #require(await store.status(ownerUID: getuid()).recovery)
        #expect(report.canRestore && report.canRemove)
        await #expect(throws: (any Error).self) { try await store.recover(.init(recordID: report.id, action: action), ownerUID: getuid() + 1) }
        try await store.recover(.init(recordID: report.id, action: action), ownerUID: getuid())
        let restored = action == .restorePrevious
        let result = try Data(contentsOf: hostsURL)
        #expect(String(decoding: result, as: UTF8.self).contains(String(decoding: external, as: UTF8.self)))
        #expect(HostsDocument.containsRegistrations(["demo.test"], in: result) == restored)
        #expect(try trust.isInstalled(der, hostnames: ["demo.test"], policy: .serverTLS) == restored)
        if restored { #expect(try Data(contentsOf: registration) == previousBytes) }
        else { #expect(!FileManager.default.fileExists(atPath: registration.path)) }
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("recovery.previous.json").path))
        #expect(try Data(contentsOf: directory.appendingPathComponent("hosts.previous")) == original)
    }

    @Test func legacyRecoveryRequiresApprovalAndPreservesChangedSections() async throws {
        let root = try temporaryDirectory(" legacy recovery")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("helper")
        try PrivateFiles.directory(directory)
        let identity = UUID(), der = Data("CA".utf8)
        let record: [String: Any] = ["schemaVersion": 3, "ownerUID": getuid(), "installationID": identity.uuidString,
            "hostnames": ["demo.test"], "certificateDER": der.base64EncodedString(), "trustPolicy": "serverTLS"]
        try PrivateFiles.write(JSONSerialization.data(withJSONObject: record), to: directory.appendingPathComponent("pending.json"))
        let hostsURL = root.appendingPathComponent("hosts")
        let changed = Data("# BEGIN JERD\n127.0.0.1 outside.test\n# END JERD\n".utf8)
        try changed.write(to: hostsURL)
        let store = PrivilegedSetupStore(directory: directory, expectedFileOwner: getuid(),
            hosts: AtomicHostsFile(url: hostsURL, expectedOwner: getuid()), certificates: MemoryTrust())
        var report = try #require(await store.status(ownerUID: getuid()).recovery)
        #expect(!report.canRestore && !report.canRemove)
        await #expect(throws: (any Error).self) { try await store.recover(.init(recordID: report.id, action: .removeSetup), ownerUID: getuid()) }
        #expect(try Data(contentsOf: hostsURL) == changed)
        await #expect(throws: (any Error).self) { try await store.status(ownerUID: getuid() + 1) }
        try HostsDocument.replacing(Data(), hostnames: ["demo.test"], expectedHostnames: []).write(to: hostsURL)
        report = try #require(await store.status(ownerUID: getuid()).recovery)
        #expect(!report.canRestore && report.canRemove)
        try await store.recover(.init(recordID: report.id, action: .removeSetup), ownerUID: getuid())
        #expect(try Data(contentsOf: hostsURL).isEmpty)
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
    var waitingForAcquire = false
    var pauseAcquire = false
    var acquireWaiter: CheckedContinuation<Void, Never>?
    var pauseConfigure = false
    var waitingForConfigure = false
    var configureWaiter: CheckedContinuation<Void, Never>?
    func suspendConfiguration() { pauseConfigure = true }
    func resumeConfiguration() { configureWaiter?.resume(); configureWaiter = nil }
    func suspendAcquisition() { pauseAcquire = true }
    func resumeAcquisition() { acquireWaiter?.resume(); acquireWaiter = nil }
    init(_ snapshot: SystemSetupStatus) { self.snapshot = snapshot }
    func status() -> SystemSetupStatus { snapshot }
    func configure(_ request: SystemRegistrationRequest) async {
        if pauseConfigure {
            waitingForConfigure = true
            await withCheckedContinuation { configureWaiter = $0 }
            pauseConfigure = false
        }
        snapshot = SystemSetupStatus(hostnames: request.hostnames, installationID: request.installationID,
            certificateSHA256: InstallationCertificate.fingerprint(request.certificateDER), certificateDER: request.certificateDER,
            hostsConfigured: true, trustConfigured: true, trustPolicy: request.trustPolicy)
    }
    func acquireListeners() async throws -> ListeningSockets {
        acquired += 1
        if pauseAcquire {
            waitingForAcquire = true
            await withCheckedContinuation { acquireWaiter = $0 }
            pauseAcquire = false
        }
        return try ListeningSockets.bind(httpPort: 0, httpsPort: 0)
    }
    func releaseListeners() { released += 1 }
    func removeSetup() { snapshot = SystemSetupStatus() }
}

private actor FakeEngine: EngineServing {
    var state: EnvironmentState = .stopped
    var starts = 0
    var startedSiteIDs: Set<UUID> = []
    var preflights = 0
    var failNextStart = false
    func rejectNextStart() { failNextStart = true }
    func preflight(_ configuration: WebConfiguration, paths: EnginePaths) { preflights += 1 }
    func start(sites: [SiteRuntime], caddy: CaddyRuntime, paths: EnginePaths,
               httpsPort: UInt16, httpPort: UInt16, listeningSockets: ListeningSockets?) throws {
        starts += 1
        if failNextStart { failNextStart = false; throw JerdError.process("Injected startup failure") }
        startedSiteIDs = Set(sites.map { $0.site.id })
        state = .running
    }
    func requestStop() {}
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

private struct NoListeners: CommandRunning {
    func run(_ request: ProcessRequest, timeout: Duration) -> CommandResult {
        CommandResult(status: 1, output: "")
    }
}

struct EnvironmentTests {
    @Test func stopDuringRollbackListenerAcquisitionPreventsEngineStartup() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = UUID(), der = Data("test CA".utf8)
        try PrivateFiles.write(Data(identity.uuidString.utf8), to: root.appendingPathComponent("installation-id"))
        let caDir = root.appendingPathComponent("certificates/pki/authorities/jerd")
        try PrivateFiles.directory(caDir)
        try Data("-----BEGIN CERTIFICATE-----\n\(der.base64EncodedString())\n-----END CERTIFICATE-----".utf8)
            .write(to: caDir.appendingPathComponent("root.crt"))
        let system = FakeSystem(SystemSetupStatus(hostname: "demo.test", installationID: identity,
            certificateSHA256: InstallationCertificate.fingerprint(der), certificateDER: der,
            hostsConfigured: true, trustConfigured: true, trustPolicy: .serverTLS))
        await system.suspendAcquisition()
        let engine = FakeEngine()
        let environment = LocalEnvironment(directory: root, system: system, engine: engine, probe: FakeProbe(), commands: NoListeners())
        let runtime = DevelopmentRuntime(cliPath: "/usr/bin/true", fpmPath: "/usr/bin/true", version: "8.5.11", architectures: [.current], cliExtensions: [], fpmExtensions: [])
        let plan = WebConfiguration(sites: [SiteRuntime(site: makeSite(root), runtime: runtime)],
            caddy: CaddyRuntime(path: "/usr/bin/true", version: "2.11.4", architectures: [.current]))
        let restore = Task { try await environment.restoreRun(plan) }
        while await !system.waitingForAcquire { await Task.yield() }
        let releasesBeforeAcquisition = await system.released
        await environment.requestStop()
        await system.resumeAcquisition()
        await #expect(throws: CancellationError.self) { try await restore.value }
        #expect(await engine.starts == 0)
        #expect(await system.released == releasesBeforeAcquisition + 1)
        await environment.stop()
    }

    @Test func unchangedSettingsKeepHealthyProcessesAndChangedExecutablesRestart() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = UUID(), der = Data("test CA".utf8)
        try PrivateFiles.write(Data(identity.uuidString.utf8), to: root.appendingPathComponent("installation-id"))
        let caDir = root.appendingPathComponent("certificates/pki/authorities/jerd")
        try PrivateFiles.directory(caDir)
        try Data("-----BEGIN CERTIFICATE-----\n\(der.base64EncodedString())\n-----END CERTIFICATE-----".utf8)
            .write(to: caDir.appendingPathComponent("root.crt"))
        let binary = root.appendingPathComponent("binary")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: binary)
        let system = FakeSystem(SystemSetupStatus(hostname: "demo.test", installationID: identity,
            certificateSHA256: InstallationCertificate.fingerprint(der), certificateDER: der,
            hostsConfigured: true, trustConfigured: true, trustPolicy: .serverTLS))
        let engine = FakeEngine()
        let environment = LocalEnvironment(directory: root, system: system, engine: engine, probe: FakeProbe(), commands: NoListeners())
        let runtime = DevelopmentRuntime(cliPath: binary.path, fpmPath: binary.path, version: "8.5.11", architectures: [.current], cliExtensions: [], fpmExtensions: [])
        let caddy = CaddyRuntime(path: binary.path, version: "2.11.4", architectures: [.current])
        var site = makeSite(root)
        let plan = WebConfiguration(sites: [SiteRuntime(site: site, runtime: runtime)], caddy: caddy)
        let prepared = try await environment.preflight(plan)
        try await environment.ensure(plan, prepared: prepared)
        site.displayName = "New display name"
        try await environment.ensure(WebConfiguration(sites: [SiteRuntime(site: site, runtime: runtime)], caddy: caddy))
        #expect(await engine.starts == 1)
        #expect(await engine.preflights == 1)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 1)], ofItemAtPath: binary.path)
        try await environment.ensure(WebConfiguration(sites: [SiteRuntime(site: site, runtime: runtime)], caddy: caddy))
        #expect(await engine.starts == 2)
        await environment.requestStop()
        await #expect(throws: CancellationError.self) { try await environment.restoreRun(plan) }
        #expect(await engine.starts == 2)
        await environment.stop()
    }

    @Test(arguments: ["success", "failure", "stop"])
    func selectedSitesSurviveApprovalAndStop(mode: String) async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let identity = UUID(), der = Data("test CA".utf8)
        try PrivateFiles.write(Data(identity.uuidString.utf8), to: root.appendingPathComponent("installation-id"))
        let caDir = root.appendingPathComponent("certificates/pki/authorities/jerd")
        try PrivateFiles.directory(caDir)
        try Data("-----BEGIN CERTIFICATE-----\n\(der.base64EncodedString())\n-----END CERTIFICATE-----".utf8)
            .write(to: caDir.appendingPathComponent("root.crt"))
        let binary = root.appendingPathComponent("binary")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: binary)
        let system = FakeSystem(SystemSetupStatus(hostname: "one.test", installationID: identity,
            certificateSHA256: InstallationCertificate.fingerprint(der), certificateDER: der,
            hostsConfigured: true, trustConfigured: true, trustPolicy: .serverTLS))
        let engine = FakeEngine()
        let environment = LocalEnvironment(directory: root, system: system, engine: engine, probe: FakeProbe(), commands: NoListeners())
        let runtime = DevelopmentRuntime(cliPath: binary.path, fpmPath: binary.path, version: "8.5.11", architectures: [.current], cliExtensions: [], fpmExtensions: [])
        let caddy = CaddyRuntime(path: binary.path, version: "2.11.4", architectures: [.current])
        let secondRoot = root.appendingPathComponent("second")
        try PrivateFiles.directory(secondRoot)
        let one = makeSite(root, hostname: "one.test"), two = makeSite(secondRoot, hostname: "two.test")
        let first = WebConfiguration(sites: [SiteRuntime(site: one, runtime: runtime)], caddy: caddy)
        let both = WebConfiguration(sites: first.sites + [SiteRuntime(site: two, runtime: runtime)], caddy: caddy)
        try await environment.ensure(first)
        let setup = HTTPSSetup(sites: [one, two], request: SystemRegistrationRequest(installationID: identity,
            hostnames: [one.hostname, two.hostname], certificateDER: der, trustPolicy: .serverTLS))
        if mode == "failure" {
            await engine.rejectNextStart()
            await #expect(throws: (any Error).self) { try await environment.approveAndStart(both, setup: setup) }
            #expect(await environment.snapshot().siteIDs == [one.id])
        } else if mode == "stop" {
            await system.suspendConfiguration()
            let task = Task { try await environment.approveAndStart(both, setup: setup) }
            while await !system.waitingForConfigure { await Task.yield() }
            await environment.requestStop()
            await system.resumeConfiguration()
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(await engine.starts == 1)
            #expect(await environment.snapshot().siteIDs.isEmpty == true)
        } else {
            try await environment.approveAndStart(both, setup: setup)
            #expect(await environment.snapshot().siteIDs == [one.id, two.id])
            try await environment.ensure(WebConfiguration(sites: [both.sites[1]], caddy: caddy))
            #expect(await environment.snapshot().siteIDs == [two.id])
        }
        await environment.stop()
        #expect(await environment.snapshot().siteIDs.isEmpty == true)
    }

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
        let environment = LocalEnvironment(directory: root, system: system, engine: engine, probe: probe, commands: NoListeners())
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
        let environment = LocalEnvironment(directory: root, system: system, engine: engine, probe: FakeProbe(fail: fail),
                                           commands: NoListeners())
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
