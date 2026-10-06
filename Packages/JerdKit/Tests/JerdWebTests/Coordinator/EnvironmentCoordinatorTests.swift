import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct EnvironmentCoordinatorTests {
    @Test func anApprovedPlanStartsAndEveryHostnameIsChecked() async throws {
        let harness = try CoordinatorHarness(approved: ["one.test", "two.test"])
        defer { harness.remove() }
        let two = try harness.site("two.test")
        let one = try harness.site("one.test")
        try await harness.ensure(harness.plan([two, one]))
        #expect(
            await harness.coordinator.snapshot() == EnvironmentSnapshot(state: .running, siteIDs: [one.id, two.id]))
        #expect(Set(await harness.probe.checked) == ["one.test", "two.test"])
        #expect(await harness.system.acquired == 1)
        await harness.coordinator.stop()
        #expect(await harness.system.released == 1)
        #expect(await harness.coordinator.snapshot() == EnvironmentSnapshot(state: .stopped, siteIDs: []))
    }

    @Test(arguments: [
        ([String](), HTTPSTrustPolicy.serverTLS, false), (["one.test"], .serverTLS, true),
        (["demo.test"], .hostnames, true),
    ])
    func anUnapprovedPlanStartsNothing(
        _ hostnames: [String], _ policy: HTTPSTrustPolicy, _ configured: Bool
    )
        async throws
    {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        await harness.system.set(configured ? try FakeSystem.approved(hostnames, policy: policy) : HTTPSSetupStatus())
        await #expect(throws: JerdError.unavailable("Approve HTTPS setup for the changed sites before activation.")) {
            try await harness.ensure(harness.plan([try harness.site("demo.test")]))
        }
        #expect(await harness.engine.starts == 0)
        #expect(await harness.system.acquired == 0)
    }

    @Test func aPendingRecoveryOrAnotherCABlocksActivationAndKeepsTheRun() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        let site = try harness.site("demo.test")
        try await harness.ensure(harness.plan([site]))
        var recovering = try FakeSystem.approved(["demo.test"])
        recovering.hasPendingRecovery = true
        await harness.system.set(recovering)
        var renamed = site
        renamed.documentRoot = try harness.folder.folder("projects/demo.test/public").path
        await #expect(throws: JerdError.self) { try await harness.ensure(harness.plan([renamed])) }
        var foreign = try FakeSystem.approved(["demo.test"])
        foreign.certificateSHA256 = String(repeating: "0", count: 64)
        await harness.system.set(foreign)
        await #expect(
            throws: JerdError.unavailable(
                "The local CA does not match the approved HTTPS setup. The active sites were kept running.")
        ) { try await harness.ensure(harness.plan([renamed])) }
        #expect(await harness.coordinator.snapshot().siteIDs == [site.id])
        #expect(await harness.engine.starts == 1)
    }

    /// Review web-r1 M2: keeping a run activates nothing, so a later CA change does not refuse
    /// it. A rollback can then keep the run that a refused activation never stopped.
    @Test(arguments: [false, true])
    func aHealthyEquivalentRunIsKeptAfterTheLocalCAChanged(_ removeCA: Bool) async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        let plan = harness.plan([try harness.site("demo.test")])
        try await harness.ensure(plan)
        let file = harness.layout.environment.rootCertificateFile
        if removeCA {
            try FileManager.default.removeItem(at: file)
        } else {
            try AtomicFile.write(try Certificates.pem("other-ca"), to: file)
        }
        try await harness.ensure(plan)
        #expect(await harness.engine.starts == 1)
        #expect(await harness.coordinator.snapshot().state == .running)
        var renamed = plan.sites[0].site
        renamed.documentRoot = try harness.folder.folder("projects/demo.test/public").path
        await #expect(
            throws: JerdError.unavailable(
                "The local CA does not match the approved HTTPS setup. The active sites were kept running.")
        ) { try await harness.ensure(harness.plan([renamed])) }
        #expect(await harness.coordinator.snapshot().siteIDs == [plan.siteIDs.first!])
    }

    @Test func anUnchangedHealthyRunIsKeptAndAChangedExecutableRestarts() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        var site = try harness.site("demo.test")
        let prepared = try await harness.coordinator.preflight(
            harness.plan([site]), ticket: await harness.coordinator.ticket())
        try await harness.ensure(harness.plan([site]), prepared: prepared)
        site.displayName = "New display name"
        try await harness.ensure(harness.plan([site]))
        #expect(await harness.engine.starts == 1)
        #expect(await harness.engine.preflights == 1)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 5)], ofItemAtPath: harness.binary.path)
        try await harness.ensure(harness.plan([site]))
        #expect(await harness.engine.starts == 2)
        #expect(await harness.engine.preflights == 2)
    }

    @Test func aPreparedTokenIsUsedOnceAndOnlyForItsPlan() async throws {
        let harness = try CoordinatorHarness(approved: ["one.test", "two.test"])
        defer { harness.remove() }
        let one = try harness.site("one.test")
        let two = try harness.site("two.test")
        let ticket = await harness.coordinator.ticket()
        let prepared = try await harness.coordinator.preflight(harness.plan([one]), ticket: ticket)
        try await harness.ensure(harness.plan([two]), prepared: prepared)
        #expect(await harness.engine.preflights == 2)
        try await harness.ensure(harness.plan([one]), prepared: prepared)
        #expect(await harness.engine.preflights == 2)
        try await harness.ensure(harness.plan([one, two]), prepared: prepared)
        #expect(await harness.engine.preflights == 3)
    }

    @Test func aRuntimeChangeDuringPreflightIsRefused() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        let binary = harness.binary
        await harness.engine.setOnPreflight {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: 9)], ofItemAtPath: binary.path)
        }
        await #expect(throws: JerdError.unavailable("A runtime changed during preparation. Retry the change.")) {
            try await harness.coordinator.preflight(
                harness.plan([try harness.site("demo.test")]), ticket: await harness.coordinator.ticket())
        }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: harness.layout.environment.root.path)
        #expect(!leftovers.contains { $0.hasPrefix("preflight-") })
    }

    @Test func aTrustFailureStopsTheEngineAndReleasesTheListeners() async throws {
        let harness = try CoordinatorHarness(probeFails: true)
        defer { harness.remove() }
        await #expect(throws: JerdError.unavailable("System trust test failed")) {
            try await harness.ensure(harness.plan([try harness.site("demo.test")]))
        }
        #expect(await harness.engine.state == .stopped)
        #expect(await harness.system.acquired == 1)
        #expect(await harness.system.released == 1)
        #expect(await harness.coordinator.snapshot().state == .failed("System trust test failed"))
    }

    @Test func anEngineCrashAfterSuccessFailsTheEnvironmentOnce() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        try await harness.ensure(harness.plan([try harness.site("demo.test")]))
        await harness.engine.crash()
        #expect(await waitUntil { await harness.coordinator.snapshot().state == .failed("test exit") })
        #expect(await harness.system.released == 1)
        await harness.coordinator.stop()
        #expect(await harness.system.released == 1)
    }

    @Test func anEmptyPlanStopsTheRun() async throws {
        let harness = try CoordinatorHarness()
        defer { harness.remove() }
        try await harness.ensure(harness.plan([try harness.site("demo.test")]))
        try await harness.ensure(harness.plan([]))
        #expect(await harness.coordinator.snapshot().state == .stopped)
        #expect(await harness.system.released == 1)
    }
}
