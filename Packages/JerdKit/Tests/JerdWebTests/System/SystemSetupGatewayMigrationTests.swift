import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@testable import JerdWeb

/// The CA update of an installation whose approved setup trusts the CA that Caddy made.
@Suite struct SystemSetupGatewayMigrationTests {
    /// A gateway with the legacy fixture CA installed and, by default, approved for `a.test`.
    private func legacyContext(_ status: HTTPSSetupStatus? = nil) async throws -> SystemSetupGatewayTests.Context {
        let context = try SystemSetupGatewayTests.Context(try status ?? FakeSystem.approved(["a.test"]))
        let environment = context.layout.environment
        try OwnedDirectory.create(environment.root)
        try AtomicFile.write(Data(Certificates.installationID.uuidString.utf8), to: environment.installationIDFile)
        try Certificates.install(in: environment)
        return context
    }

    private func retiredFolders(_ environment: EnvironmentLayout) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            atPath: environment.authorityDirectory("x").deletingLastPathComponent().path
        ).filter { $0.hasPrefix("jerd-retired-") }
    }

    @Test func theUpdateTrustsJerdsCARetiresTheLegacyCAAndKeepsTheSetup() async throws {
        let context = try await legacyContext()
        defer { context.folder.remove() }
        let environment = context.layout.environment
        let prepared = try await context.gateway.prepareCAMigration()
        #expect(try await context.gateway.localAuthority()?.signsOnlyTestNames == false)
        try await context.gateway.migrateCA()
        let replacement = try #require(await context.system.replacements.first)
        #expect(replacement.hostnames == ["a.test"] && replacement.trustPolicy == .serverTLS)
        #expect(LocalCertificateAuthority.fingerprint(of: replacement.certificateDER) == prepared.fingerprint)
        #expect(await context.coordinator.halts == 1)
        #expect(FileProbe.presence(at: environment.legacyRootCertificateFile) == .absent)
        #expect(try retiredFolders(environment).count == 1)
        let active = try #require(try await context.gateway.localAuthority())
        #expect(active.fingerprint == prepared.fingerprint && active.signsOnlyTestNames)
    }

    /// A refused replacement moves the legacy CA back, so the app and the helper still agree.
    @Test func aRefusedUpdateKeepsTheLegacyCA() async throws {
        let context = try await legacyContext()
        defer { context.folder.remove() }
        let legacy = try await context.gateway.localAuthority()
        await context.system.failNextReplace()
        await #expect(throws: JerdError.self) { try await context.gateway.migrateCA() }
        #expect(try await context.gateway.localAuthority() == legacy)
        #expect(try retiredFolders(context.layout.environment).isEmpty)
    }

    /// An installation that already uses Jerd's CA, or whose helper trusts another CA, has
    /// nothing to update; nothing moves.
    @Test func aSetupWithoutTheLegacyCAIsNotUpdated() async throws {
        let context = try await legacyContext()
        defer { context.folder.remove() }
        var other = await context.system.status()
        other.certificateSHA256 = String(repeating: "0", count: 64)
        await context.system.set(other)
        await #expect(
            throws: JerdError.unavailable("This HTTPS setup has no CA to update. Check the HTTPS setup again.")
        ) { try await context.gateway.migrateCA() }
        #expect(await context.system.replacements.isEmpty)
        #expect(FileProbe.presence(at: context.layout.environment.legacyRootCertificateFile) == .present)
    }

    /// The helper replaced the CA, but its reply got lost: the update is done, and the legacy
    /// CA stays retired, so the app and the helper name the same CA.
    @Test func aLostReplyAfterTheReplacementCountsAsDone() async throws {
        let context = try await legacyContext()
        defer { context.folder.remove() }
        let prepared = try await context.gateway.prepareCAMigration()
        await context.system.loseNextReplaceReply()
        try await context.gateway.migrateCA()
        #expect(try await context.gateway.localAuthority()?.fingerprint == prepared.fingerprint)
        #expect(try retiredFolders(context.layout.environment).count == 1)
    }

    /// A folder that cannot move back gives one message that names it and keeps the first error.
    @Test func aBlockedMoveBackNamesTheRetiredFolder() async throws {
        let context = try await legacyContext()
        defer { context.folder.remove() }
        let environment = context.layout.environment
        await context.system.failNextReplace(
            occupying: environment.authorityDirectory(EnvironmentLayout.legacyAuthorityID))
        await #expect {
            try await context.gateway.migrateCA()
        } throws: { error in
            guard let error = error as? JerdError, error.kind == .partialChange else { return false }
            return error.message.contains("Test replacement failure") && error.message.contains("jerd-retired-")
        }
        #expect(try retiredFolders(environment).count == 1)
    }

    /// The helper trusts no new unconstrained CA. Without a setup, for example after Remove System
    /// Setup, the next setup retires the legacy CA and asks for Jerd's CA for `.test` names.
    @Test func aNewSetupRetiresAnUntrustedLegacyCA() async throws {
        let context = try await legacyContext(HTTPSSetupStatus())
        defer { context.folder.remove() }
        let setup = try await context.gateway.prepare(hostnames: ["a.test"], caddy: Samples.caddy())
        let active = try #require(try await context.gateway.localAuthority())
        #expect(active.signsOnlyTestNames)
        #expect(LocalCertificateAuthority.fingerprint(of: setup.registration.certificateDER) == active.fingerprint)
        #expect(try retiredFolders(context.layout.environment).count == 1)
    }

    /// An approved legacy CA stays until the CA update, and so does one that a recovery could
    /// trust again.
    @Test(arguments: [false, true])
    func aSetupThatMayTrustTheLegacyCAKeepsIt(pendingRecovery: Bool) async throws {
        let status = pendingRecovery ? HTTPSSetupStatus(hasPendingRecovery: true) : try FakeSystem.approved(["a.test"])
        let context = try await legacyContext(status)
        defer { context.folder.remove() }
        let legacy = try await context.gateway.localAuthority()
        _ = try await context.gateway.prepare(hostnames: ["a.test"], caddy: Samples.caddy())
        #expect(try await context.gateway.localAuthority() == legacy)
        #expect(try retiredFolders(context.layout.environment).isEmpty)
    }

    /// A running Caddy may still use the legacy CA, so nothing moves while it runs.
    @Test func anUntrustedLegacyCAStaysWhileTheEnvironmentRuns() async throws {
        let context = try SystemSetupGatewayTests.Context(
            HTTPSSetupStatus(), running: ServingPlan(sites: [], caddy: Samples.caddy()))
        defer { context.folder.remove() }
        let environment = context.layout.environment
        try OwnedDirectory.create(environment.root)
        try AtomicFile.write(Data(Certificates.installationID.uuidString.utf8), to: environment.installationIDFile)
        try Certificates.install(in: environment)
        await #expect(throws: JerdError.unavailable("Stop the sites before Jerd retires its old CA.")) {
            try await context.gateway.prepare(hostnames: ["a.test"], caddy: Samples.caddy())
        }
        #expect(FileProbe.presence(at: environment.legacyRootCertificateFile) == .present)
    }

    /// A rollback after the last site removed the legacy setup cannot trust the legacy CA again,
    /// so it asks for a new approval and changes nothing.
    @Test func aRollbackDoesNotSetUpARemovedLegacyCAAgain() async throws {
        let context = try await legacyContext(HTTPSSetupStatus())
        defer { context.folder.remove() }
        await #expect(
            throws: JerdError.unavailable("The HTTPS setup was removed. Approve HTTPS again for these sites.")
        ) {
            try await context.gateway.restore(try FakeSystem.approved(["a.test"]))
        }
        #expect(await context.system.configurations.isEmpty)
    }
}
