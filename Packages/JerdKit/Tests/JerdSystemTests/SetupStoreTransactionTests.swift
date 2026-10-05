import Darwin
import Foundation
import JerdFoundation
import Testing

@testable import JerdSystem

@Suite struct SetupStoreTransactionTests {
    private let owner = StoreHarness.owner

    @Test func configureWritesHostsTrustAndVersionThreeRecord() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let store = harness.store()
        try await store.configure(harness.request(["b.test", "a.test"]), ownerUID: owner, trust: harness.trust)
        let status = try await store.status(ownerUID: owner)
        #expect(status.hostnames == ["a.test", "b.test"] && status.isReadyForServing)
        #expect(status.certificateSHA256 == FileDigest.hexSHA256(of: try Fixture.certificate()))
        let saved = try #require(harness.record(.registration))
        #expect(
            try JSONSerialization.jsonObject(with: saved) as? NSDictionary == [
                "schemaVersion": 3, "ownerUID": 501,
                "installationID": Fixture.installationID.uuidString, "hostnames": ["a.test", "b.test"],
                "certificateDER": try Fixture.certificate().base64EncodedString(), "trustPolicy": "serverTLS",
            ])
        #expect(harness.record(.pending) == nil)
        #expect(harness.record(.hostsBackup) == nil)
        #expect(
            harness.hosts == StoreHarness.originalHosts
                + Data(HostsSection.render(try Fixture.hostnames("a.test", "b.test")).utf8))
    }

    @Test func aFailedInstallRestoresTheExactStatusAndBytes() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let store = harness.store()
        harness.trust.failNextInstall(.unavailable)
        await #expect(throws: JerdError.unavailable("Test trust failure")) {
            try await store.configure(harness.request(["demo.test"]), ownerUID: owner, trust: harness.trust)
        }
        #expect(harness.hosts == StoreHarness.originalHosts)
        #expect(try await store.status(ownerUID: owner) == .empty)
        #expect(harness.record(.pending) == nil)
    }

    /// A v1 or v2 record stays byte for byte when its upgrade fails, and the upgrade writes v3.
    @Test(arguments: ["registration-v1", "registration-v2"])
    func legacyRecordUpgradeKeepsTheBytesUntilItSucceeds(name: String) async throws {
        let legacy = try Fixture.data("Records/\(name).json")
        let record = try HelperRecordCodec.decodeRegistration(legacy)
        let harness = try StoreHarness(
            hosts: try HostsSection.replacing(
                in: StoreHarness.originalHosts, with: record.hostnames.values, expecting: []))
        defer { harness.remove() }
        try harness.directory.write(legacy, to: .registration)
        harness.trust.seed(try record.trust())
        let store = harness.store()
        let before = try await store.status(ownerUID: owner)
        #expect(before.trustConfigured && before.hostsConfigured && before.trustPolicy == .hostnames)
        let upgrade = try harness.request(record.hostnames.strings + ["new.test"])
        harness.trust.failNextInstall(.partial)
        await #expect(throws: JerdError.self) {
            try await store.configure(upgrade, ownerUID: owner, trust: harness.trust)
        }
        #expect(harness.record(.registration) == legacy)
        #expect(try await store.status(ownerUID: owner) == before)
        try await store.configure(upgrade, ownerUID: owner, trust: harness.trust)
        #expect(try await store.status(ownerUID: owner).trustPolicy == .serverTLS)
        #expect(
            try HelperRecordCodec.decodeRegistration(#require(harness.record(.registration))).trustPolicy == .serverTLS)
    }

    @Test func aChangedHostSetKeepsTheCAAndRollsBack() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let store = harness.store()
        try await store.configure(harness.request(["old.test", "new.test"]), ownerUID: owner, trust: harness.trust)
        let snapshot = try await store.status(ownerUID: owner)
        harness.trust.failNextInstall(.unavailable)
        await #expect(throws: JerdError.self) {
            try await store.configure(harness.request(["other.test"]), ownerUID: owner, trust: harness.trust)
        }
        #expect(try await store.status(ownerUID: owner) == snapshot)
        try await store.configure(harness.request(["other.test"]), ownerUID: owner, trust: harness.trust)
        #expect(try await store.status(ownerUID: owner).hostnames == ["other.test"])
        try await store.remove(ownerUID: owner, trust: harness.trust)
        #expect(harness.hosts == StoreHarness.originalHosts)
        #expect(try await store.status(ownerUID: owner) == .empty)
        #expect(harness.trust.installed(try Fixture.certificate()) == nil)
    }

    @Test func refusesAnotherCAAnotherOwnerAndRoot() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let store = harness.store()
        try await store.configure(harness.request(["demo.test"]), ownerUID: owner, trust: harness.trust)
        await #expect(throws: JerdError.invalid("Remove the previous Jerd system setup before replacing its CA.")) {
            try await store.configure(
                harness.request(["demo.test"], certificate: "jerd-ca-other"), ownerUID: owner, trust: harness.trust)
        }
        await #expect(throws: JerdError.unavailable("The system setup belongs to another user.")) {
            try await store.remove(ownerUID: owner + 1, trust: harness.trust)
        }
        await #expect(throws: JerdError.invalid("Root cannot own a Jerd project environment.")) {
            try await store.configure(harness.request(["demo.test"]), ownerUID: 0, trust: harness.trust)
        }
        await #expect(throws: JerdError.self) {
            try await store.configure(harness.request(["demo.test"]), ownerUID: 499, trust: harness.trust)
        }
    }

    @Test func removeWithoutSetupDoesNothing() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        try await harness.store().remove(ownerUID: owner, trust: harness.trust)
        #expect(harness.trust.calls.isEmpty)
        #expect(harness.hosts == StoreHarness.originalHosts)
    }

    @Test func aFailedRemovalReinstallsTrustAndHosts() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let store = harness.store()
        try await store.configure(harness.request(["demo.test"]), ownerUID: owner, trust: harness.trust)
        let configured = try await store.status(ownerUID: owner)
        let bytes = harness.record(.registration)
        harness.trust.failNextRemoval(.partial)
        await #expect(throws: JerdError.unavailable("Test partial removal failure")) {
            try await store.remove(ownerUID: owner, trust: harness.trust)
        }
        #expect(try await store.status(ownerUID: owner) == configured)
        #expect(harness.record(.registration) == bytes)
        #expect(harness.record(.pending) == nil)
    }

    /// Fixed problem 7: the retained phase says what was rolled back.
    @Test func interruptedConsentKeepsTheJournalAndNamesTheRollback() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let store = harness.store()
        harness.trust.failNextInstall(.interrupted)
        do {
            try await store.configure(harness.request(["demo.test"]), ownerUID: owner, trust: harness.trust)
            Issue.record("Expected a failure")
        } catch let error as JerdError {
            #expect(error.kind == .partialChange)
            #expect(
                error.message.hasPrefix(
                    "Setup failed and needs recovery. The helper retained its backup. Test app disconnect"))
            #expect(error.message.contains("Its result is unknown"))
        }
        #expect(harness.hosts == StoreHarness.originalHosts)
        let recovery = try #require(try await store.status(ownerUID: owner).recovery)
        #expect(recovery.phase == "Certificate approval started; its result may be unknown. Rolled back: host entries.")
        #expect(recovery.canRestore && recovery.canRemove)
        try await store.recover(
            .init(recordID: recovery.id, action: .restorePrevious), ownerUID: owner, trust: harness.trust)
        #expect(try await store.status(ownerUID: owner) == .empty)
        #expect(harness.hosts == StoreHarness.originalHosts)
    }

    @Test func aPartialInstallWithAFailedCleanupKeepsTheJournal() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        harness.trust.failNextInstall(.partial)
        harness.trust.failNextRemoval(.unavailable)
        await #expect(throws: JerdError.self) {
            try await harness.store().configure(harness.request(["demo.test"]), ownerUID: owner, trust: harness.trust)
        }
        #expect(harness.hosts == StoreHarness.originalHosts)
        let phase = try #require(try await harness.store().status(ownerUID: owner).recovery?.phase)
        #expect(
            phase
                == "Certificate approval started; its result may be unknown. Rolled back: host entries. Rollback failed: certificate trust."
        )
    }

    @Test(arguments: [false, true])
    func aHostsRaceDuringRestorationKeepsTheJournalAndOneStagingFile(removing: Bool) async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let request = try harness.request(["demo.test"])
        if removing { try await harness.store().configure(request, ownerUID: owner, trust: harness.trust) }
        let before = harness.hosts
        let raced = before + Data("127.0.0.1 raced.test\n".utf8)
        let url = harness.hostsURL
        let store = harness.store(
            hooks: GuardedFileSwapHooks(
                preExchange: { try raced.write(to: url, options: .atomic) },
                preRestore: { throw JerdError.unavailable("Injected restoration failure") }))
        await #expect(throws: JerdError.self) {
            if removing {
                try await store.remove(ownerUID: owner, trust: harness.trust)
            } else {
                try await store.configure(request, ownerUID: owner, trust: harness.trust)
            }
        }
        #expect(harness.record(.hostsBackup) == before)
        let recovery = try #require(try await store.status(ownerUID: owner).recovery)
        #expect(recovery.phase.hasPrefix("Host replacement needs recovery: The hosts file changed during setup."))
        let retained = try harness.folder.names(withPrefix: ".jerd-hosts-")
        #expect(retained.count == 1)
        #expect(try Data(contentsOf: harness.folder.path(try #require(retained.first))) == raced)
        #expect((harness.trust.installed(try Fixture.certificate()) != nil) == removing)
    }

    /// Fixed problem 3: status during a transaction reports it as running, not interrupted.
    @Test func statusDuringATransactionReportsItInProgress() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let gate = BlockingTrust(harness.trust)
        let store = harness.store()
        let task = Task { try await store.configure(harness.request(["demo.test"]), ownerUID: owner, trust: gate) }
        await gate.waitUntilInstallStarts()
        let status = try await store.status(ownerUID: owner)
        #expect(status.operationInProgress == "Configure HTTPS")
        #expect(status.recovery == nil)
        await #expect(throws: JerdError.unavailable("Wait for the current system operation to finish.")) {
            try await store.remove(ownerUID: owner, trust: harness.trust)
        }
        gate.release()
        try await task.value
        #expect(try await store.status(ownerUID: owner).isReadyForServing)
    }
}
