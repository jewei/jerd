import Foundation
import JerdFoundation
import Security
import Testing
import os

@testable import JerdSystem

@Suite struct HelperClientTests {
    private final class AcceptingTrustSettings: TrustSettingsApplying {
        func setAdminTrust(certificateDER: Data, scope: TrustScope) -> OSStatus { errSecSuccess }
        func removeAdminTrust(certificateDER: Data) -> OSStatus { errSecSuccess }
    }

    private func client(_ helper: FakeHelper, _ status: HelperAvailability = .enabled) -> (HelperClient, FakeLinkOpener)
    {
        let opener = FakeLinkOpener(helper)
        let registration = HelperRegistration(service: FakeDaemonService(status)) {}
        return (
            HelperClient(registration: registration, opener: opener, trustSettings: AcceptingTrustSettings()), opener
        )
    }

    private func certificate() throws -> InstallationCertificate {
        try InstallationCertificate(installationID: Fixture.installationID, der: Fixture.certificate())
    }

    private func configured(
        _ hostnames: [String], policy: CertificateTrustPolicy = .hostnames
    ) throws -> SystemSetupStatus {
        SystemSetupStatus(
            hostnames: hostnames, installationID: Fixture.installationID, certificateDER: try Fixture.certificate(),
            hostsConfigured: true, trustConfigured: true, trustPolicy: policy)
    }

    @Test func aDisabledHelperGivesItsStateWithoutAnXPCCall() async throws {
        let helper = FakeHelper()
        let (client, opener) = client(helper, .requiresApproval)
        #expect(try await client.status() == HelperStatus(availability: .requiresApproval, setup: .empty))
        #expect(opener.opened.withLock { $0 } == 0)
        await #expect(throws: JerdError.unavailable("Approved helper setup is required.")) {
            try await client.acquireListeners()
        }
    }

    @Test func statusDecodesTheSetupAndMapsErrors() async throws {
        let helper = FakeHelper(.init(status: try configured(["a.test"])))
        let (client, opener) = client(helper)
        #expect(try await client.status().setup.hostnames == ["a.test"])
        _ = try await client.status()
        #expect(opener.opened.withLock { $0 } == 1)
        helper.script.withLock { $0.statusError = "The hosts file changed. (JERD-INVALID)" }
        await #expect(throws: JerdError.invalid("The hosts file changed.")) { try await client.status() }
        helper.script.withLock { $0.statusError = "Old helper text" }
        await #expect(throws: JerdError.unavailable("Old helper text")) { try await client.status() }
    }

    @Test func aTransportErrorHasTheReconnectMessage() async throws {
        let helper = FakeHelper(.init(transportFailure: true))
        let (client, _) = client(helper)
        await #expect(throws: HelperConnection.transportError(NSError(domain: NSCocoaErrorDomain, code: 4_097))) {
            try await client.status()
        }
    }

    @Test func configureAllowsTheNewAndCurrentHostsOfTheSameCA() async throws {
        let consent = TrustConsentRequest(
            certificateDER: try Fixture.certificate(), hostnames: ["old.test"], policy: .hostnames)
        let helper = FakeHelper(.init(status: try configured(["old.test"]), consentRequest: consent))
        let (client, _) = client(helper)
        try await client.configure(
            hostnames: try ValidatedHostnames(["new.test"]), caCertificate: certificate(), policy: .serverTLS)
        #expect(helper.received.withLock { $0.consentStatuses } == [errSecSuccess])
        let request = try JSONDecoder().decode(
            SystemRegistrationRequest.self, from: #require(helper.received.withLock { $0.payloads.first }))
        #expect(request.hostnames == ["new.test"] && request.trustPolicy == .serverTLS)
        #expect(!client.gate.allows(consent))
    }

    @Test func configureRefusesTrustOutsideTheApprovedScope() async throws {
        let consent = TrustConsentRequest(
            certificateDER: try Fixture.certificate(), hostnames: ["other.test"], policy: .serverTLS)
        let helper = FakeHelper(.init(consentRequest: consent))
        let (client, _) = client(helper)
        await #expect(throws: JerdError.self) {
            try await client.configure(
                hostnames: try ValidatedHostnames(["new.test"]), caCertificate: certificate(), policy: .serverTLS)
        }
        #expect(helper.received.withLock { $0.consentStatuses } == [errSecAuthFailed])
    }

    @Test func helperErrorsKeepTheirKind() async throws {
        let helper = FakeHelper(.init(changeError: "Setup failed and needs recovery. (JERD-PARTIAL-CHANGE)"))
        let (client, _) = client(helper)
        await #expect(throws: JerdError.partialChange("Setup failed and needs recovery.")) {
            try await client.configure(
                hostnames: try ValidatedHostnames(["a.test"]), caCertificate: certificate(), policy: .serverTLS)
        }
    }

    @Test func removeAllowsOnlyTheRecordedSetup() async throws {
        let removal = TrustConsentRequest.removal(of: try Fixture.certificate())
        let helper = FakeHelper(.init(status: try configured(["a.test"], policy: .serverTLS), consentRequest: removal))
        let (client, _) = client(helper)
        try await client.removeSetup()
        #expect(helper.calls == ["status", "remove"])
        #expect(helper.received.withLock { $0.consentStatuses } == [errSecSuccess])
        helper.script.withLock { $0.status = .empty }
        await #expect(throws: JerdError.self) { try await client.removeSetup() }
        #expect(helper.received.withLock { $0.consentStatuses }.last == errSecAuthFailed)
    }

    @Test func recoverSendsTheRecordIDAndRefusesAnUnreadableRecord() async throws {
        let helper = FakeHelper()
        let (client, _) = client(helper)
        let report = SystemRecoveryStatus(
            id: "abc", operation: "Configure HTTPS", phase: "p", details: [], canRestore: true, canRemove: true,
            installationID: Fixture.installationID, certificateDER: try Fixture.certificate(), previousHostnames: [],
            intendedHostnames: ["a.test"], policies: [.serverTLS])
        try await client.recover(report: report, action: .removeSetup)
        let approval = try JSONDecoder().decode(
            SystemRecoveryApproval.self, from: #require(helper.received.withLock { $0.payloads.last }))
        #expect(approval == SystemRecoveryApproval(recordID: "abc", action: .removeSetup))
        let unreadable = RecoveryAssessor.unreadable(id: "x", reason: "bad", location: URL(fileURLWithPath: "/tmp/p"))
        await #expect(
            throws: JerdError.unavailable("The recovery record cannot be read. An administrator must inspect it.")
        ) {
            try await client.recover(report: unreadable, action: .removeSetup)
        }
    }

    @Test func acquireReturnsTheListenersAndReleaseSkipsWithoutAConnection() async throws {
        let pair = try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
        defer { pair.close() }
        let helper = FakeHelper(.init(listeners: pair))
        let (client, _) = client(helper)
        await client.releaseListeners()
        #expect(helper.calls.isEmpty)
        let received = try await client.acquireListeners()
        #expect(try received.ports() == pair.ports())
        await client.releaseListeners()
        #expect(helper.calls == ["acquire", "release"])
        helper.script.withLock { $0.listeners = nil }
        await #expect(throws: JerdError.unavailable("No ports")) { try await client.acquireListeners() }
    }

    @Test func aStaleCloseEventDoesNotDropANewerConnection() async throws {
        let helper = FakeHelper()
        let (client, opener) = client(helper)
        _ = try await client.status()
        await client.invalidate()
        _ = try await client.status()
        let handlers = opener.closeHandlers.withLock { $0 }
        handlers[0]()
        try await Task.sleep(for: .milliseconds(20))
        _ = try await client.status()
        #expect(opener.opened.withLock { $0 } == 2)
        handlers[1]()
        try await Task.sleep(for: .milliseconds(20))
        _ = try await client.status()
        #expect(opener.opened.withLock { $0 } == 3)
    }

    /// Regression test: a 20-second call that times out does not drop the one shared link while a
    /// change on it waits for macOS approval. Without a waiting change, a timeout still drops it.
    @Test func aTimeoutKeepsTheLinkWhileAChangeWaitsForApproval() async throws {
        let (client, opener) = client(FakeHelper())
        let connection = client.connection
        let held = OSAllocatedUnfairLock<ReplyGate<Bool>?>(initialState: nil)
        let change = Task { () async throws -> Bool in
            try await connection.call(timeout: nil) { _, gate in held.withLock { $0 = gate } }
        }
        while held.withLock({ $0 }) == nil { try await Task.sleep(for: .milliseconds(5)) }
        let unanswered: @Sendable (any JerdHelperProtocol, ReplyGate<Bool>) -> Void = { _, _ in }
        await #expect(throws: ReplyGate<Bool>.timeoutError) {
            try await connection.call(timeout: .milliseconds(20), unanswered)
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(await connection.isConnected)
        held.withLock { $0 }?.resolve(.success(true))
        #expect(try await change.value)
        await #expect(throws: ReplyGate<Bool>.timeoutError) {
            try await connection.call(timeout: .milliseconds(20), unanswered)
        }
        for _ in 0..<100 where await connection.isConnected { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!(await connection.isConnected))
        #expect(opener.opened.withLock { $0 } == 1)
    }

    @Test func aCancelledStatusReturnsPromptly() async throws {
        let helper = FakeHelper(.init(unanswered: true))
        let (client, _) = client(helper)
        let task = Task { try await client.status() }
        try await Task.sleep(for: .milliseconds(20))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func reconnectAndUnregisterUseTheRegistration() async throws {
        let service = FakeDaemonService(.enabled)
        let client = HelperClient(
            registration: HelperRegistration(service: service) {}, opener: FakeLinkOpener(FakeHelper()))
        try await client.reconnect()
        try await client.unregister()
        #expect(service.calls == ["unregister", "register", "unregister"])
        try await HelperClient(registration: HelperRegistration(service: FakeDaemonService(.notFound)) {}).approve()
    }
}
