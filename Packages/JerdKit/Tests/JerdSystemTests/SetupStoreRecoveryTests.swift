import Darwin
import Foundation
import JerdFoundation
import Testing

@testable import JerdSystem

@Suite struct SetupStoreRecoveryTests {
    private let owner = StoreHarness.owner
    private let external = Data("10.0.0.9 outside.test\n".utf8)

    private func record(_ hostnames: [String], policy: CertificateTrustPolicy = .serverTLS) throws -> RegistrationRecord
    {
        RegistrationRecord(
            ownerUID: owner, installationID: Fixture.installationID, hostnames: try ValidatedHostnames(hostnames),
            certificateDER: try Fixture.certificate(), trustPolicy: policy)
    }

    private func writeJournal(
        _ harness: StoreHarness, _ operation: SetupOperation, previous: RegistrationRecord?, previousBytes: Data? = nil,
        intended: RegistrationRecord?, hostsBefore: Data, phase: String
    ) throws {
        let bytes = try previousBytes ?? previous.map { try HelperRecordCodec.encode($0) }
        let journal = SetupJournal(
            operation: operation, previous: previous, previousBytes: bytes, intended: intended,
            hostsSHA256: FileDigest.hexSHA256(of: hostsBefore), phase: phase)
        try harness.directory.write(HelperRecordCodec.encode(journal), to: .pending)
        try harness.directory.write(hostsBefore, to: .hostsBackup)
    }

    @Test(arguments: ["prepared", "hosts", "trust", "registration"])
    func anInterruptedFirstSetupRestoresToNothingAndKeepsExternalEdits(stage: String) async throws {
        let original = StoreHarness.originalHosts
        let intended = try record(["demo.test"])
        let changed =
            stage == "prepared"
            ? original : try HostsSection.replacing(in: original, with: intended.hostnames.values, expecting: [])
        let harness = try StoreHarness(hosts: changed + external)
        defer { harness.remove() }
        try writeJournal(harness, .configure, previous: nil, intended: intended, hostsBefore: original, phase: stage)
        if stage == "trust" || stage == "registration" { harness.trust.seed(try intended.trust()) }
        if stage == "registration" {
            try harness.directory.write(HelperRecordCodec.encode(intended), to: .registration)
        }
        let store = harness.store()
        let report = try #require(try await store.status(ownerUID: owner).recovery)
        #expect(report.canRestore && report.canRemove)
        await #expect(
            throws: JerdError.unavailable("The recovery record changed. Inspect it and approve recovery again.")
        ) {
            try await store.recover(
                .init(recordID: "stale", action: .restorePrevious), ownerUID: owner, trust: harness.trust)
        }
        try await store.recover(
            .init(recordID: report.id, action: .restorePrevious), ownerUID: owner, trust: harness.trust)
        #expect(harness.hosts == original + external)
        #expect(try await store.status(ownerUID: owner) == .empty)
        #expect(harness.trust.installed(try Fixture.certificate()) == nil)
        #expect(harness.record(.recoveryCopy) != nil && harness.record(.hostsBackup) == original)
    }

    @Test(arguments: ["prepared", "hosts", "trust", "registration"], SystemRecoveryAction.allCases)
    func anInterruptedRemovalCanRestoreOrFinish(stage: String, action: SystemRecoveryAction) async throws {
        let previous = try record(["demo.test"])
        let plain = StoreHarness.originalHosts
        let original = try HostsSection.replacing(in: plain, with: previous.hostnames.values, expecting: [])
        let harness = try StoreHarness(hosts: (stage == "prepared" ? original : plain) + external)
        defer { harness.remove() }
        // Pretty-printed bytes prove that a restore writes the exact earlier file, not a new encoding.
        let previousBytes = try JSONSerialization.data(
            withJSONObject: JSONSerialization.jsonObject(with: HelperRecordCodec.encode(previous)),
            options: [.prettyPrinted])
        try writeJournal(
            harness, .remove, previous: previous, previousBytes: previousBytes, intended: nil, hostsBefore: original,
            phase: stage)
        if stage == "prepared" || stage == "hosts" { harness.trust.seed(try previous.trust()) }
        if stage != "registration" { try harness.directory.write(previousBytes, to: .registration) }
        let store = harness.store()
        let report = try #require(try await store.status(ownerUID: owner).recovery)
        #expect(report.canRestore && report.canRemove)
        await #expect(throws: JerdError.self) {
            try await store.recover(
                .init(recordID: report.id, action: action), ownerUID: owner + 1, trust: harness.trust)
        }
        try await store.recover(.init(recordID: report.id, action: action), ownerUID: owner, trust: harness.trust)
        let restored = action == .restorePrevious
        #expect(String(decoding: harness.hosts, as: UTF8.self).contains("10.0.0.9 outside.test"))
        #expect(HostsSection.maps(previous.hostnames.values, in: harness.hosts) == restored)
        #expect((harness.trust.installed(try Fixture.certificate()) != nil) == restored)
        #expect(harness.record(.registration) == (restored ? previousBytes : nil))
        #expect(harness.record(.pending) == nil && harness.record(.recoveryCopy) != nil)
    }

    /// Regression test: an external mapping of a recorded hostname does not block a recovery removal,
    /// because the removal adds no hostname. A restore that would add a mapped hostname is refused.
    @Test func anExternalMappingBlocksOnlyARestoreThatAddsItsHostname() async throws {
        let plain = StoreHarness.originalHosts
        let previous = try record(["old.test"])
        let intended = try record(["demo.test"])
        let original = try HostsSection.replacing(in: plain, with: previous.hostnames.values, expecting: [])
        let outside = Data("10.0.0.1 demo.test\n10.0.0.2 old.test\n".utf8)
        let written = try HostsSection.replacing(in: plain, with: intended.hostnames.values, expecting: [])
        let harness = try StoreHarness(hosts: written + outside)
        defer { harness.remove() }
        try writeJournal(harness, .configure, previous: previous, intended: intended, hostsBefore: original, phase: "h")
        try harness.directory.write(HelperRecordCodec.encode(previous), to: .registration)
        let store = harness.store()
        let report = try #require(try await store.status(ownerUID: owner).recovery)
        #expect(!report.canRestore && report.canRemove)
        #expect(report.details.contains { $0.hasPrefix("The current Jerd host section matches a recorded state.") })
        try await store.recover(.init(recordID: report.id, action: .removeSetup), ownerUID: owner, trust: harness.trust)
        #expect(harness.hosts == plain + outside)
        #expect(try await store.status(ownerUID: owner) == .empty)
    }

    @Test func aLegacyRecordCanOnlyBeRemovedAndOnlyWhenTheSectionMatches() async throws {
        let changed = Data("# BEGIN JERD\n127.0.0.1 outside.test\n# END JERD\n".utf8)
        let harness = try StoreHarness(hosts: changed)
        defer { harness.remove() }
        try harness.directory.write(Fixture.data("Records/pending-legacy.json"), to: .pending)
        let store = harness.store()
        var report = try #require(try await store.status(ownerUID: owner).recovery)
        #expect(report.operation == "Interrupted legacy HTTPS setup" && report.phase == "Unknown")
        #expect(!report.canRestore && !report.canRemove)
        await #expect(
            throws: JerdError.unavailable(
                "The recorded system state needs manual inspection. No recovery change was made.")
        ) {
            try await store.recover(
                .init(recordID: report.id, action: .removeSetup), ownerUID: owner, trust: harness.trust)
        }
        #expect(harness.hosts == changed)
        try Data(HostsSection.render(try Fixture.hostnames("shop.test")).utf8).write(to: harness.hostsURL)
        report = try #require(try await store.status(ownerUID: owner).recovery)
        #expect(!report.canRestore && report.canRemove)
        try await store.recover(.init(recordID: report.id, action: .removeSetup), ownerUID: owner, trust: harness.trust)
        #expect(harness.hosts == Data())
    }

    /// Regression test: a corrupt journal gives a report that names the file; nothing is changed.
    @Test func aCorruptJournalGivesASpecificReportAndIsPreserved() async throws {
        let harness = try StoreHarness(hosts: Data("keep".utf8))
        defer { harness.remove() }
        let corrupt = Data(#"{"schemaVersion":1,"operation":"Configure HTTPS","phase":"x"}"#.utf8)
        try harness.directory.write(corrupt, to: .pending)
        let store = harness.store()
        let report = try #require(try await store.status(ownerUID: owner).recovery)
        #expect(
            report.details.first
                == "The helper recovery record is invalid. It was preserved. The key hostsSHA256 is missing.")
        #expect(report.details.last?.contains(harness.directory.location(of: .pending).path) == true)
        #expect(!report.canRestore && !report.canRemove && report.installationID == nil && report.fingerprint == nil)
        await #expect(throws: JerdError.self) { try await store.remove(ownerUID: owner, trust: harness.trust) }
        await #expect(
            throws: JerdError.corrupt(
                "The helper recovery record is invalid. It was preserved. The key hostsSHA256 is missing.")
        ) {
            try await store.recover(
                .init(recordID: report.id, action: .removeSetup), ownerUID: owner, trust: harness.trust)
        }
        #expect(harness.hosts == Data("keep".utf8) && harness.record(.pending) == corrupt)
    }

    @Test func anotherUsersRecordIsNotRevealedOrRecovered() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        try writeJournal(
            harness, .configure, previous: nil, intended: try record(["demo.test"]),
            hostsBefore: StoreHarness.originalHosts, phase: "x")
        let report = try #require(try await harness.store().status(ownerUID: owner + 1).recovery)
        #expect(report.details.first == "This recovery record belongs to another user.")
        #expect(report.installationID == nil && !report.canRemove)
    }

    /// Regression test: a missing or changed backup is reported but does not block a restore.
    @Test func aMissingBackupDoesNotBlockRestore() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        try writeJournal(
            harness, .configure, previous: nil, intended: try record(["demo.test"]),
            hostsBefore: StoreHarness.originalHosts, phase: "prepared")
        try harness.directory.remove(.hostsBackup)
        let report = try #require(try await harness.store().status(ownerUID: owner).recovery)
        #expect(report.canRestore)
        #expect(
            report.details.contains(
                "The original host-file backup is missing or changed. Recovery uses only the current Jerd host section."
            ))
    }

    /// Regression test: a second attempt keeps the first copy of the journal.
    @Test func aRetryKeepsTheFirstJournalCopy() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let intended = try record(["demo.test"])
        try writeJournal(
            harness, .configure, previous: nil, intended: intended, hostsBefore: StoreHarness.originalHosts,
            phase: "prepared")
        let original = try #require(harness.record(.pending))
        harness.trust.failNextRemoval(.unavailable)
        let store = harness.store()
        var report = try #require(try await store.status(ownerUID: owner).recovery)
        await #expect(throws: JerdError.unavailable("Test removal failure")) {
            try await store.recover(
                .init(recordID: report.id, action: .removeSetup), ownerUID: owner, trust: harness.trust)
        }
        report = try #require(try await store.status(ownerUID: owner).recovery)
        #expect(report.phase == "Recovery host entries were written; certificate change is pending")
        try await store.recover(.init(recordID: report.id, action: .removeSetup), ownerUID: owner, trust: harness.trust)
        #expect(harness.record(.recoveryCopy) == original)
    }

    /// Regression test: policies have one stable order.
    @Test func recoveryPoliciesAreSorted() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let previous = try record(["demo.test"], policy: .hostnames)
        let hosts = try HostsSection.replacing(
            in: StoreHarness.originalHosts, with: previous.hostnames.values, expecting: [])
        try Data(hosts).write(to: harness.hostsURL)
        try harness.directory.write(HelperRecordCodec.encode(previous), to: .registration)
        try writeJournal(
            harness, .configure, previous: previous, intended: try record(["demo.test"]), hostsBefore: hosts, phase: "p"
        )
        #expect(try await harness.store().status(ownerUID: owner).recovery?.policies == [.hostnames, .serverTLS])
    }

    @Test func aDifferentSavedRegistrationBlocksBothActions() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        try writeJournal(
            harness, .configure, previous: nil, intended: try record(["demo.test"]),
            hostsBefore: StoreHarness.originalHosts, phase: "p")
        try harness.directory.write(HelperRecordCodec.encode(try record(["other.test"])), to: .registration)
        let report = try #require(try await harness.store().status(ownerUID: owner).recovery)
        #expect(!report.canRestore && !report.canRemove)
        #expect(report.details.first == "The saved registration differs from this transaction. Inspect it manually.")
    }
}
