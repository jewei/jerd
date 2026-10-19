import CryptoKit
import Darwin
import Foundation
import JerdFoundation
import Testing

@testable import JerdSystem

/// A CA replacement: the new CA may sign only `.test` names, and the old CA keeps working until
/// the replacement commits.
@Suite struct SetupStoreReplaceCATests {
    private let owner = StoreHarness.owner

    /// Jerd's CA of the fixture installation, with or without the name constraints.
    static func jerdCA(constrained: Bool = true) throws -> Data {
        let key = P256.Signing.PrivateKey()
        let name = CertificateIdentity.commonName(for: Fixture.installationID)
        guard constrained else {
            return try CertificateBuilder(
                subjectCommonName: name, issuerCommonName: name, publicKey: key.publicKey,
                serialNumber: CertificateBuilder.randomSerialNumber(), notBefore: Date(),
                notAfter: Date().addingTimeInterval(86_400),
                extensions: LocalRootTemplate.caExtensions(for: key.publicKey)
            ).signed(by: key)
        }
        return try LocalRootTemplate.certificate(commonName: name, key: key, now: Date())
    }

    private func replacement(
        _ harness: StoreHarness, _ der: Data, hostnames: [String] = ["demo.test"]
    ) -> SystemRegistrationRequest {
        SystemRegistrationRequest(
            installationID: Fixture.installationID, hostnames: hostnames, certificateDER: der, trustPolicy: .serverTLS)
    }

    @Test func theReplacementTrustsTheNewCARemovesTheOldOneAndKeepsTheHosts() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let store = harness.store()
        try await store.configure(harness.request(["demo.test"]), ownerUID: owner, trust: harness.trust)
        let hosts = harness.hosts
        let new = try Self.jerdCA()
        try await store.replaceCA(replacement(harness, new), ownerUID: owner, trust: harness.trust)
        let status = try await store.status(ownerUID: owner)
        #expect(status.certificateSHA256 == FileDigest.hexSHA256(of: new) && status.hostnames == ["demo.test"])
        #expect(harness.trust.installed(new) != nil)
        #expect(harness.trust.installed(try Fixture.certificate()) == nil)
        #expect(harness.hosts == hosts)
        #expect(harness.record(.pending) == nil)
    }

    @Test func onlyAConstrainedCAOfTheSameSetupCanReplaceTheCA() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let store = harness.store()
        await #expect(throws: JerdError.invalid("There is no Jerd system setup whose CA can be replaced.")) {
            try await store.replaceCA(replacement(harness, try Self.jerdCA()), ownerUID: owner, trust: harness.trust)
        }
        try await store.configure(harness.request(["demo.test"]), ownerUID: owner, trust: harness.trust)
        let bytes = harness.record(.registration)
        await #expect(
            throws: JerdError.invalid("Only a Jerd CA that may sign only .test names can replace the current CA.")
        ) {
            try await store.replaceCA(
                replacement(harness, try Self.jerdCA(constrained: false)), ownerUID: owner, trust: harness.trust)
        }
        await #expect(throws: JerdError.self) {
            try await store.replaceCA(
                replacement(harness, try Self.jerdCA(), hostnames: ["other.test"]), ownerUID: owner,
                trust: harness.trust)
        }
        await #expect(throws: JerdError.invalid("The new CA is the same as the current CA.")) {
            try await store.replaceCA(
                replacement(harness, try Fixture.certificate()), ownerUID: owner, trust: harness.trust)
        }
        #expect(harness.record(.registration) == bytes)
        #expect(harness.trust.installed(try Fixture.certificate()) != nil)
    }

    /// A failed removal of the old CA puts its trust back and removes the new CA.
    @Test func aFailedReplacementKeepsTheOldCAWorking() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let store = harness.store()
        try await store.configure(harness.request(["demo.test"]), ownerUID: owner, trust: harness.trust)
        let configured = try await store.status(ownerUID: owner)
        let bytes = harness.record(.registration)
        let new = try Self.jerdCA()
        harness.trust.failNextRemoval(.partial)
        await #expect(throws: JerdError.self) {
            try await store.replaceCA(replacement(harness, new), ownerUID: owner, trust: harness.trust)
        }
        #expect(try await store.status(ownerUID: owner) == configured)
        #expect(harness.record(.registration) == bytes)
        #expect(harness.trust.installed(try Fixture.certificate()) != nil)
        #expect(harness.trust.installed(new) == nil)
        #expect(harness.record(.pending) == nil)
    }

    /// An interrupted approval keeps the journal. Restore trusts the old CA again and removes the
    /// new one; remove takes both away.
    @Test(arguments: [SystemRecoveryAction.restorePrevious, .removeSetup])
    func anInterruptedReplacementRecoversWithBothCAs(action: SystemRecoveryAction) async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let store = harness.store()
        try await store.configure(harness.request(["demo.test"]), ownerUID: owner, trust: harness.trust)
        let bytes = harness.record(.registration)
        let new = try Self.jerdCA()
        harness.trust.failNextRemoval(.interrupted)
        await #expect(throws: JerdError.self) {
            try await store.replaceCA(replacement(harness, new), ownerUID: owner, trust: harness.trust)
        }
        let old = try Fixture.certificate()
        let report = try #require(try await store.status(ownerUID: owner).recovery)
        #expect(report.operation == "Replace HTTPS CA" && report.previousCertificateDER == old)
        try await store.recover(.init(recordID: report.id, action: action), ownerUID: owner, trust: harness.trust)
        #expect(harness.trust.installed(new) == nil)
        #expect((harness.trust.installed(old) != nil) == (action == .restorePrevious))
        #expect(harness.record(.registration) == (action == .restorePrevious ? bytes : nil))
        #expect(harness.record(.pending) == nil)
    }

    /// A replacement journal with an unconstrained new CA is never accepted for recovery.
    @Test func aReplacementJournalWithAnUnconstrainedCAIsPreserved() async throws {
        let harness = try StoreHarness()
        defer { harness.remove() }
        let old = RegistrationRecord(
            ownerUID: owner, installationID: Fixture.installationID, hostnames: try ValidatedHostnames(["demo.test"]),
            certificateDER: try Fixture.certificate(), trustPolicy: .serverTLS)
        let new = RegistrationRecord(
            ownerUID: owner, installationID: Fixture.installationID, hostnames: old.hostnames,
            certificateDER: try Self.jerdCA(constrained: false), trustPolicy: .serverTLS)
        let journal = SetupJournal(
            operation: .replaceCA, previous: old, previousBytes: try HelperRecordCodec.encode(old), intended: new,
            hostsSHA256: FileDigest.hexSHA256(of: harness.hosts), phase: "test")
        try harness.directory.write(HelperRecordCodec.encode(journal), to: .pending)
        let report = try #require(try await harness.store().status(ownerUID: owner).recovery)
        #expect(!report.canRestore && !report.canRemove)
        #expect(report.operation == "Unreadable HTTPS setup record")
        #expect(harness.record(.pending) != nil)
    }
}
