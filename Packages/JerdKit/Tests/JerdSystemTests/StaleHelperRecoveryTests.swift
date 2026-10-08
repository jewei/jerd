import Foundation
import JerdFoundation
import Security
import Testing
import os

@testable import JerdSystem

/// The app recovers by itself from a helper that still runs the code from before an app update.
@Suite(.timeLimit(.minutes(1))) struct StaleHelperRecoveryTests {
    private final class AcceptingTrustSettings: TrustSettingsApplying {
        func setAdminTrust(certificateDER: Data, scope: TrustScope) -> OSStatus { errSecSuccess }
        func removeAdminTrust(certificateDER: Data) -> OSStatus { errSecSuccess }
    }

    private static let stale = HelperTransportError(NSError(domain: NSCocoaErrorDomain, code: 4_102))
    private static let lost = HelperTransportError(NSError(domain: NSCocoaErrorDomain, code: 4_099))

    private func configuredHelper() throws -> FakeHelper {
        FakeHelper(
            .init(
                status: SystemSetupStatus(
                    hostnames: ["games-jp.test"], installationID: Fixture.installationID,
                    certificateDER: try Fixture.certificate(), hostsConfigured: true, trustConfigured: true,
                    trustPolicy: .serverTLS)))
    }

    private func client(
        _ helper: FakeHelper, daemon: FakeDaemonService, script: FakeUpdatedHelperOpener.Script = .init(),
        gate: PauseGate? = nil
    ) -> (HelperClient, FakeUpdatedHelperOpener) {
        let opener = FakeUpdatedHelperOpener(helper: helper, daemon: daemon, script: script)
        let registration =
            gate.map { gate in
                HelperRegistration(service: daemon, processes: daemon, requireSignedBuild: {}) { await gate.pause($0) }
            } ?? daemon.registration()
        let client = HelperClient(registration: registration, opener: opener, trustSettings: AcceptingTrustSettings())
        return (client, opener)
    }

    /// Lets started tasks run until they wait, without waiting for real time.
    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    /// Regression test: calls that start while the automatic restart runs wait for it. Before,
    /// a status read "not registered, no setup", an acquire failed with "Approved helper setup is
    /// required", and an approval registered the daemon in parallel with the restart.
    @Test func callsThatStartDuringTheRestartWaitForIt() async throws {
        let pair = try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
        defer { pair.close() }
        let helper = try configuredHelper()
        helper.script.withLock { $0.listeners = pair }
        let daemon = FakeDaemonService(.enabled)
        daemon.configure { $0.exitingChecks = 1 }
        let gate = PauseGate()
        let (client, _) = client(helper, daemon: daemon, gate: gate)
        let first = Task { try await client.status() }
        await gate.waitUntilPaused()
        #expect(daemon.status == .notRegistered)
        let second = Task { try await client.status() }
        let acquire = Task { try await client.acquireListeners() }
        let approve = Task { try await client.approve() }
        await settle()
        gate.open()
        #expect(try await first.value.setup.hostnames == ["games-jp.test"])
        let status = try await second.value
        #expect(status.availability == .enabled && status.setup.hostnames == ["games-jp.test"])
        try await acquire.value.close()
        try await approve.value
        #expect(daemon.calls == ["unregister", "register"])
    }

    /// A reply that XPC refuses after the restart already finished came from the old helper: the
    /// call is sent again on the new link, not reported as a helper that stays stale.
    @Test func aFailureOnALinkFromBeforeTheRestartIsRetriedOnTheNewLink() async throws {
        let daemon = FakeDaemonService(.enabled)
        let (client, opener) = client(try configuredHelper(), daemon: daemon, script: .init(heldStaleCalls: 1))
        let early = Task { try await client.status() }
        while opener.heldCount == 0 { await Task.yield() }
        #expect(try await client.status().setup.hostnames == ["games-jp.test"])
        opener.releaseHeldFailures()
        #expect(try await early.value.setup.hostnames == ["games-jp.test"])
        #expect(daemon.registrations == 1)
    }

    /// A manual Reconnect during the automatic restart reuses it, and a later stale helper can be
    /// restarted automatically again.
    @Test func aManualReconnectDuringTheRestartReusesIt() async throws {
        let daemon = FakeDaemonService(.enabled)
        daemon.configure { $0.exitingChecks = 1 }
        let gate = PauseGate()
        let (client, opener) = client(try configuredHelper(), daemon: daemon, gate: gate)
        let first = Task { try await client.status() }
        await gate.waitUntilPaused()
        let reconnected = OSAllocatedUnfairLock(initialState: false)
        let reconnect = Task {
            try await client.reconnect()
            reconnected.withLock { $0 = true }
        }
        await settle()
        // No second registration runs in parallel: the Reconnect ends only with the running restart.
        #expect(!reconnected.withLock { $0 })
        gate.open()
        _ = try await first.value
        try await reconnect.value
        #expect(daemon.calls == ["unregister", "register"])
        opener.script.withLock { $0.currentAfterRegistrations = 2 }
        _ = try await client.status()
        #expect(daemon.registrations == 2)
    }

    /// The field sequence with fakes: the helper ran before the update and never exited, the
    /// updated app's call fails with 4102, the app restarts the helper (the old process still
    /// exits, and the first register attempt fails with EPERM), and the call succeeds.
    @Test func theAppRecoversFromAStaleHelperAfterAnUpdateWithoutTheUser() async throws {
        let helper = try configuredHelper()
        let daemon = FakeDaemonService(.enabled)
        daemon.configure {
            $0.exitingChecks = 2
            $0.refusesWhileExiting = true
            $0.registerErrors = [FakeDaemonService.operationNotPermitted]
        }
        let (client, opener) = client(helper, daemon: daemon)
        let status = try await client.status()
        #expect(status.setup.hostnames == ["games-jp.test"])
        #expect(daemon.calls == ["unregister", "register", "register"])
        #expect(daemon.registrations == 1 && daemon.status == .enabled)
        #expect(opener.opened == 2)
        // The next calls use the new connection; nothing restarts again.
        _ = try await client.status()
        #expect(daemon.calls.count == 3 && opener.opened == 2)
        #expect(helper.calls == ["status", "status"])
    }

    @Test func aHelperThatStaysStaleIsRestartedOnlyOnce() async throws {
        let daemon = FakeDaemonService(.enabled)
        let (client, _) = client(try configuredHelper(), daemon: daemon, script: .init(currentAfterRegistrations: nil))
        let expected = HelperRecoveryPolicy.staleAfterRestart(Self.stale)
        await #expect(throws: expected) { try await client.status() }
        await #expect(throws: expected) { try await client.status() }
        await #expect(throws: expected) { try await client.acquireListeners() }
        #expect(daemon.registrations == 1)
        #expect(daemon.calls == ["unregister", "register"])
        #expect(expected.remedy == .reconnectHelper)
        #expect(expected.message.hasSuffix("Error code: NSCocoaErrorDomain 4102."))
    }

    @Test func concurrentCallsShareOneRestart() async throws {
        let daemon = FakeDaemonService(.enabled)
        daemon.configure { $0.exitingChecks = 5 }
        let (client, _) = client(try configuredHelper(), daemon: daemon)
        async let first = client.status()
        async let second = client.status()
        async let third = client.status()
        let results = try await [first, second, third]
        #expect(results.allSatisfy { $0.setup.hostnames == ["games-jp.test"] })
        #expect(daemon.registrations == 1 && daemon.calls == ["unregister", "register"])
    }

    @Test func aManualReconnectAllowsALaterAutomaticRestart() async throws {
        let daemon = FakeDaemonService(.enabled)
        let (client, opener) = client(try configuredHelper(), daemon: daemon)
        _ = try await client.status()
        try await client.reconnect()
        opener.script.withLock { $0.currentAfterRegistrations = 3 }
        _ = try await client.status()
        #expect(daemon.registrations == 3)
    }

    @Test func noAutomaticRestartWhileTheSitesHoldTheListeners() async throws {
        let pair = try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
        defer { pair.close() }
        let helper = try configuredHelper()
        helper.script.withLock { $0.listeners = pair }
        let daemon = FakeDaemonService(.enabled)
        let (client, opener) = client(helper, daemon: daemon, script: .init(currentAfterRegistrations: 0))
        let received = try await client.acquireListeners()
        defer { received.close() }
        opener.script.withLock { $0.currentAfterRegistrations = nil }
        await #expect(throws: HelperRecoveryPolicy.staleWhileServing(Self.stale)) { try await client.status() }
        #expect(daemon.calls.isEmpty)
        await client.releaseListeners()
        _ = try? await client.status()
        #expect(daemon.calls == ["unregister", "register"])
    }

    @Test func aLostConnectionIsRetriedOnceOnANewConnection() async throws {
        let daemon = FakeDaemonService(.enabled)
        let (client, opener) = client(
            try configuredHelper(), daemon: daemon, script: .init(currentAfterRegistrations: 0, nextErrorCodes: [4_099])
        )
        #expect(try await client.status().setup.hostnames == ["games-jp.test"])
        #expect(opener.opened == 2 && daemon.calls.isEmpty)
        await client.invalidate()
        opener.script.withLock { $0.nextErrorCodes = [4_099, 4_099, nil] }
        await #expect(throws: Self.lost.userError) { try await client.status() }
        #expect(daemon.calls.isEmpty)
    }

    /// A change can reach the helper before XPC refuses its reply, so it is never sent twice.
    @Test func aChangeIsNeverRetriedAfterATransportFailure() async throws {
        let helper = try configuredHelper()
        let daemon = FakeDaemonService(.enabled)
        let (client, _) = client(
            helper, daemon: daemon, script: .init(currentAfterRegistrations: 0, nextErrorCodes: [nil, 4_102]))
        let certificate = try InstallationCertificate(
            installationID: Fixture.installationID, der: Fixture.certificate())
        await #expect(throws: Self.stale.userError) {
            try await client.configure(
                hostnames: try ValidatedHostnames(["games-jp.test"]), caCertificate: certificate, policy: .serverTLS)
        }
        #expect(helper.calls == ["status"] && daemon.calls.isEmpty)
    }

    @Test(arguments: [
        (HelperRecoveryPolicy.Restart.available, false, HelperRecoveryPolicy.Step.restartThenRetry),
        (.running, false, .awaitRestartThenRetry),
        (.used, false, .fail(HelperRecoveryPolicy.staleAfterRestart(stale))),
        (.used, true, .fail(HelperRecoveryPolicy.staleWhileServing(stale))),
        (.available, true, .fail(HelperRecoveryPolicy.staleWhileServing(stale))),
    ])
    func aSignatureMismatchRestartsOnlyOnceAndNeverWhileServing(
        restart: HelperRecoveryPolicy.Restart, holdsListeners: Bool, step: HelperRecoveryPolicy.Step
    ) {
        #expect(HelperRecoveryPolicy.step(after: Self.stale, restart: restart, holdsListeners: holdsListeners) == step)
    }

    @Test func aMismatchFromBeforeAFinishedRestartIsRetriedOnTheNewLink() {
        for restart in [HelperRecoveryPolicy.Restart.available, .running, .used] {
            for holds in [false, true] {
                let step = HelperRecoveryPolicy.step(
                    after: Self.stale, restart: restart, holdsListeners: holds, restartedSinceStart: true)
                #expect(step == .retryOnNewLink)
            }
        }
    }

    @Test func otherFailuresRetryOnlyALostConnection() {
        let other = HelperTransportError(NSError(domain: NSPOSIXErrorDomain, code: 1))
        for restart in [HelperRecoveryPolicy.Restart.available, .running, .used] {
            #expect(HelperRecoveryPolicy.step(after: Self.lost, restart: restart, holdsListeners: true) == .retry)
            #expect(
                HelperRecoveryPolicy.step(after: other, restart: restart, holdsListeners: false)
                    == .fail(other.userError))
        }
        #expect(HelperRecoveryPolicy.errorAfterRetry(Self.stale) == HelperRecoveryPolicy.staleAfterRestart(Self.stale))
        #expect(HelperRecoveryPolicy.errorAfterRetry(Self.lost) == Self.lost.userError)
    }

    @Test(arguments: [
        (NSCocoaErrorDomain, 4_102, HelperTransportError.Cause.signatureMismatch),
        (NSOSStatusErrorDomain, -67_050, .signatureMismatch),
        (NSCocoaErrorDomain, 4_097, .connectionLost),
        (NSCocoaErrorDomain, 4_099, .connectionLost),
        (NSCocoaErrorDomain, 4_101, .other),
        (NSPOSIXErrorDomain, 4_102, .other),
    ])
    func everyTransportErrorHasACause(domain: String, code: Int, cause: HelperTransportError.Cause) {
        #expect(HelperTransportError.classify(domain: domain, code: code) == cause)
    }

    @Test func theTransportMessageNamesOnlyVisibleControls() {
        let message = Self.lost.userError.message
        #expect(!message.contains("Choose System setup"))
        #expect(message.contains("Reconnect Helper…") && message.contains("shield button"))
        #expect(message.hasSuffix("Error code: NSCocoaErrorDomain 4099."))
        #expect(Self.lost.userError.remedy == .reconnectHelper)
    }

    /// Real XPC: a helper that does not satisfy the app's requirement fails with 4102, so the
    /// classification matches what macOS reports for a stale helper.
    @Test func realXPCReportsARequirementFailureAsASignatureMismatch() async throws {
        let pair = try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
        defer { pair.close() }
        let legacy = LegacyHelper(pair: pair, status: try Fixture.data("Wire/status-configured.json"), consent: Data())
        let requirement = try CodeSigningPolicy.requirement(
            identifier: HelperServiceIdentity.helperIdentifier, teamID: "ABCDE12345")
        let daemon = FakeDaemonService(.enabled)
        let client = HelperClient(
            registration: daemon.registration(),
            opener: RequiringLinkOpener(endpoint: legacy.listener.endpoint, requirement: requirement),
            trustSettings: AcceptingTrustSettings())
        await #expect(throws: HelperRecoveryPolicy.staleAfterRestart(Self.stale)) { try await client.status() }
        #expect(daemon.registrations == 1)
        withExtendedLifetime(legacy) {}
    }
}
