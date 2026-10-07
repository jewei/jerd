import Foundation
import JerdFoundation
import JerdTestSupport
import JerdUI
import JerdWeb
import Testing

@testable import JerdLive

@Suite("Live Sites port")
struct LiveSitesPortTests {
    struct Harness {
        let journal = CallJournal()
        let registry: FakeSiteRegistry
        let sites: RecordingSiteTransaction
        let environment: FakeEnvironment
        let gateway: FakeHTTPSSetup
        let helper: RecordingHelper
        let loginItems = RecordingLoginItems()
        let temporary: TemporaryDirectory
        let layout: DataLayout
        let port: LiveSitesPort

        init(status: HTTPSSetupStatus = HTTPSSetupStatus()) throws {
            registry = FakeSiteRegistry(SampleWeb.configuration(sites: [SampleWeb.site()]))
            sites = RecordingSiteTransaction(registry: registry, journal: journal)
            environment = FakeEnvironment(journal: journal)
            gateway = FakeHTTPSSetup(status, journal: journal)
            helper = RecordingHelper(journal: journal)
            temporary = try TemporaryDirectory()
            layout = temporary.layout
            let setup = DevelopmentRuntimeSetup(
                registry: registry, sites: sites, source: FakeDevelopmentSource(needed: false))
            port = LiveSitesPort(
                setup: setup, sites: sites, coordinator: environment, gateway: gateway, helper: helper,
                environmentLayout: layout.environment, loginItems: loginItems)
        }

        /// Removes the temporary folder of the harness. Each test calls it in a `defer`.
        func remove() { temporary.remove() }

        /// Queues a change that waits for approval; its continuation is journaled.
        func queueApproval(hostnames: [String]) async throws -> AppConfiguration {
            let saved = SampleWeb.configuration(sites: [SampleWeb.site()])
            let journal = journal
            await sites.enqueue(
                .needsApproval(try SampleWeb.setup(hostnames: hostnames)) {
                    await journal.record("transaction.approve")
                    return saved
                })
            return saved
        }
    }

    @Test func aChangeThatNeedsApprovalWaitsUnderItsApprovalID() async throws {
        let harness = try Harness(status: HTTPSSetupStatus(hostnames: ["old.test", "shop.test"]))
        defer { harness.remove() }
        _ = try await harness.queueApproval(hostnames: ["shop.test"])

        let outcome = try await harness.port.run([SampleWeb.siteID])

        guard case .needsApproval(let approval) = outcome else {
            Issue.record("Expected an approval, got \(outcome)")
            return
        }
        #expect(approval.hostnames == ["shop.test"])
        #expect(approval.removedHostnames == ["old.test"])
        #expect(approval.fingerprint == (try SampleWeb.setup(hostnames: ["shop.test"])).fingerprint)
        #expect(await harness.port.isWaiting(approval))
    }

    /// Every setup of one installation has the same ID, so the port keys changes by its own ID.
    @Test func twoWaitingChangesOfOneInstallationKeepSeparateApprovals() async throws {
        let harness = try Harness()
        defer { harness.remove() }
        _ = try await harness.queueApproval(hostnames: ["shop.test"])
        _ = try await harness.queueApproval(hostnames: ["shop.test", "blog.test"])
        guard case .needsApproval(let first) = try await harness.port.run([SampleWeb.siteID]),
            case .needsApproval(let second) = try await harness.port.run([SampleWeb.siteID])
        else { throw JerdError.invalid("No approval.") }

        await harness.port.discard(first)

        #expect(first.id != second.id)
        #expect(await !harness.port.isWaiting(first))
        #expect(await harness.port.isWaiting(second))
    }

    @Test func removedHostnamesComeFromTheStatusThatTheHelperReportsNow() async throws {
        let harness = try Harness(status: HTTPSSetupStatus(hostnames: ["shop.test"]))
        defer { harness.remove() }
        _ = try await harness.queueApproval(hostnames: ["shop.test"])
        await harness.gateway.setStatus(HTTPSSetupStatus(hostnames: ["gone.test", "shop.test"]))

        guard case .needsApproval(let approval) = try await harness.port.run([SampleWeb.siteID]) else {
            throw JerdError.invalid("No approval.")
        }

        #expect(approval.removedHostnames == ["gone.test"])
    }

    @Test func anUnreadableStatusShowsNoRemovals() async throws {
        let harness = try Harness()
        defer { harness.remove() }
        _ = try await harness.queueApproval(hostnames: ["shop.test"])
        await harness.gateway.fail(.unavailable("The helper did not answer."))

        guard case .needsApproval(let approval) = try await harness.port.run([SampleWeb.siteID]) else {
            throw JerdError.invalid("No approval.")
        }

        #expect(approval.removedHostnames.isEmpty)
    }

    @Test func approveRegistersTheHelperBeforeTheTransactionContinues() async throws {
        let harness = try Harness()
        defer { harness.remove() }
        let saved = try await harness.queueApproval(hostnames: ["shop.test"])
        guard
            case .needsApproval(let approval) = try await harness.port.apply(
                .enabled(SampleWeb.siteID, true), startIfStopped: true)
        else { throw JerdError.invalid("No approval.") }

        let configuration = try await harness.port.approve(approval)

        #expect(configuration == saved)
        #expect(await harness.journal.entries == ["transaction.apply", "helper.approve", "transaction.approve"])
        #expect(await !harness.port.isWaiting(approval))
    }

    @Test func aFailedHelperRegistrationKeepsTheChangeForARetry() async throws {
        let harness = try Harness()
        defer { harness.remove() }
        _ = try await harness.queueApproval(hostnames: ["shop.test"])
        guard case .needsApproval(let approval) = try await harness.port.run([SampleWeb.siteID]) else {
            throw JerdError.invalid("No approval.")
        }
        await harness.helper.setFailure(.unavailable("Allow Jerd in Login Items."))

        await #expect(throws: JerdError.unavailable("Allow Jerd in Login Items.")) {
            try await harness.port.approve(approval)
        }

        #expect(await harness.port.isWaiting(approval))
        #expect(await !harness.journal.entries.contains("transaction.approve"))
    }

    @Test func discardDropsTheWaitingChange() async throws {
        let harness = try Harness()
        defer { harness.remove() }
        _ = try await harness.queueApproval(hostnames: ["shop.test"])
        guard case .needsApproval(let approval) = try await harness.port.run([SampleWeb.siteID]) else {
            throw JerdError.invalid("No approval.")
        }

        await harness.port.discard(approval)

        await #expect(throws: JerdError.self) { try await harness.port.approve(approval) }
        #expect(await harness.helper.calls.isEmpty)
    }

    @Test func aCommittedChangeReturnsTheSavedConfiguration() async throws {
        let harness = try Harness()
        defer { harness.remove() }

        let outcome = try await harness.port.apply(.enabled(SampleWeb.siteID, false), startIfStopped: false)

        #expect(outcome == .committed(SampleWeb.configuration(sites: [SampleWeb.site()])))
        #expect(await harness.sites.changes == [.enabled(SampleWeb.siteID, false)])
    }

    @Test func stopEnvironmentStopsTheRunThenClosesTheHelperConnection() async throws {
        let harness = try Harness()
        defer { harness.remove() }

        try await harness.port.stopEnvironment()

        #expect(await harness.journal.entries == ["environment.stop", "helper.invalidate"])
    }

    @Test func reconnectStopsTheSitesBeforeTheHelperRegistersAgain() async throws {
        let harness = try Harness()
        defer { harness.remove() }

        try await harness.port.reconnectHelper()

        #expect(await harness.journal.entries == ["transaction.requestStop", "helper.reconnect"])
    }

    @Test func removeSystemSetupStopsRemovesThenUnregisters() async throws {
        let harness = try Harness()
        defer { harness.remove() }

        try await harness.port.removeSystemSetup()

        #expect(
            await harness.journal.entries == ["transaction.requestStop", "gateway.removeSetup", "helper.unregister"])
    }

    @Test func aFailedRemovalKeepsTheHelperRegistered() async throws {
        let harness = try Harness()
        defer { harness.remove() }
        await harness.gateway.failRemoval(.approvalInterrupted("The approval was cancelled."))

        await #expect(throws: JerdError.self) { try await harness.port.removeSystemSetup() }
        #expect(await !harness.journal.entries.contains("helper.unregister"))
    }

    @Test func logsExistOnlyAfterTheFirstRun() async throws {
        let harness = try Harness()
        defer { harness.remove() }
        #expect(await harness.port.environmentLogs() == nil)

        try FileManager.default.createDirectory(
            at: harness.layout.environment.logsDirectory, withIntermediateDirectories: true)

        #expect(await harness.port.environmentLogs() == harness.layout.environment.logsDirectory)
    }

    @Test func theLoadGoesThroughTheBundledSetup() async throws {
        let harness = try Harness()
        defer { harness.remove() }

        #expect(try await harness.port.loadConfiguration().sites == [SampleWeb.site()])
        #expect(await harness.registry.loadCount == 1)
    }

    @Test func setupStatusAndEnvironmentPassThrough() async throws {
        let harness = try Harness(status: HTTPSSetupStatus(hostnames: ["shop.test"], hostsConfigured: true))
        defer { harness.remove() }

        #expect(try await harness.port.setupStatus().hostnames == ["shop.test"])
        #expect(await harness.port.environment() == EnvironmentSnapshot(state: .stopped, siteIDs: []))
    }

    @Test func theLocalAuthorityIsReadFromTheEnvironmentFolderOnceItsCAExists() async throws {
        let harness = try Harness()
        defer { harness.remove() }
        let environment = harness.layout.environment
        #expect(try await harness.port.localAuthority() == nil)

        try OwnedDirectory.create(environment.root)
        try AtomicFile.write(Data(Fixture.installationID.uuidString.utf8), to: environment.installationIDFile)
        #expect(try await harness.port.localAuthority() == nil)

        let der = try Fixture.certificate()
        let pem =
            "-----BEGIN CERTIFICATE-----\n\(der.base64EncodedString(options: .lineLength64Characters))\n"
            + "-----END CERTIFICATE-----\n"
        try OwnedDirectory.create(environment.rootCertificateFile.deletingLastPathComponent())
        try AtomicFile.write(Data(pem.utf8), to: environment.rootCertificateFile)
        #expect(
            try await harness.port.localAuthority()
                == InstallationAuthority(
                    installationID: Fixture.installationID, fingerprint: FileDigest.hexSHA256(of: der)))
    }

    @Test func aCorruptCACertificateIsReportedAndPreserved() async throws {
        let harness = try Harness()
        defer { harness.remove() }
        let environment = harness.layout.environment
        try OwnedDirectory.create(environment.root)
        try AtomicFile.write(Data(Fixture.installationID.uuidString.utf8), to: environment.installationIDFile)
        try OwnedDirectory.create(environment.rootCertificateFile.deletingLastPathComponent())
        try AtomicFile.write(Data("not a certificate".utf8), to: environment.rootCertificateFile)

        await #expect(throws: JerdError.self) { try await harness.port.localAuthority() }
        #expect(try Data(contentsOf: environment.rootCertificateFile) == Data("not a certificate".utf8))
    }

    @Test func loginItemsOpenThroughTheOpener() async throws {
        let harness = try Harness()
        defer { harness.remove() }

        await harness.port.openLoginItems()

        #expect(await harness.loginItems.openCount == 1)
    }

    @Test func theDocumentRootSuggestionReadsOnlyTheProjectFolder() async throws {
        let harness = try Harness()
        defer { harness.remove() }
        let project = harness.temporary.path("project")
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("public"), withIntermediateDirectories: true)
        for file in ["artisan", "composer.json", "public/index.php"] {
            FileManager.default.createFile(atPath: project.appendingPathComponent(file).path, contents: Data())
        }

        let suggestion = try await harness.port.suggestDocumentRoot(projectPath: project.path)

        #expect(suggestion.isLaravel)
        #expect(suggestion.path.hasSuffix("/public"))
    }
}
