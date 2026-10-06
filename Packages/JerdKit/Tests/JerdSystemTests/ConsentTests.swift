import Foundation
import JerdFoundation
import Security
import Testing
import os

@testable import JerdSystem

@Suite struct ConsentTests {
    private final class RecordingTrustSettings: TrustSettingsApplying {
        let calls = OSAllocatedUnfairLock(initialState: [String]())
        let status: OSStatus

        init(status: OSStatus = errSecSuccess) { self.status = status }

        func setAdminTrust(certificateDER: Data, scope: TrustScope) -> OSStatus {
            calls.withLock { $0.append("set \(scope.policy.rawValue)") }
            return status
        }

        func removeAdminTrust(certificateDER: Data) -> OSStatus {
            calls.withLock { $0.append("remove") }
            return status
        }
    }

    private func certificate(_ name: String = "jerd-ca") throws -> InstallationCertificate {
        try InstallationCertificate(
            installationID: name == "jerd-ca" ? Fixture.installationID : Fixture.otherInstallationID,
            der: Fixture.certificate(name))
    }

    private func scope(
        _ hostnames: [String] = ["old.test", "new.test"], policies: Set<CertificateTrustPolicy> = [.serverTLS]
    )
        throws -> ConsentScope
    {
        try ConsentScope(certificate: certificate(), hostnames: hostnames, policies: policies)
    }

    private func request(
        _ hostnames: [String]?, policy: CertificateTrustPolicy = .serverTLS, name: String = "jerd-ca"
    )
        throws -> TrustConsentRequest
    {
        TrustConsentRequest(certificateDER: try Fixture.certificate(name), hostnames: hostnames, policy: policy)
    }

    @Test func scopeAllowsOnlyTheApprovedCAHostsAndPolicies() throws {
        let scope = try scope()
        #expect(scope.allows(try request(["old.test"])))
        #expect(scope.allows(try request(["old.test", "new.test"])))
        #expect(scope.allows(try request(nil)))
        #expect(!scope.allows(try request([])))
        #expect(!scope.allows(try request(["old.test", "old.test"])))
        #expect(!scope.allows(try request(["new.test", "other.test"])))
        #expect(!scope.allows(try request(["old.test"], policy: .hostnames)))
        #expect(!scope.allows(try request(["old.test"], name: "jerd-ca-other")))
        #expect(!scope.allows(try request(nil, name: "jerd-ca-other")))
    }

    @Test func scopeValidatesItsHostnames() throws {
        #expect(throws: JerdError.self) { try scope(["not a host"]) }
    }

    @Test func theGateHasOneScopeAtATimeAndOnlyItsTokenClosesIt() throws {
        let gate = ConsentGate()
        #expect(!gate.allows(try request(["old.test"])))
        let token = try gate.open(scope())
        #expect(gate.allows(try request(["old.test"])))
        #expect(throws: JerdError.unavailable("Wait for the current system operation to finish.")) {
            try gate.open(scope())
        }
        gate.close(ConsentToken())
        #expect(gate.allows(try request(["old.test"])))
        gate.close(token)
        #expect(!gate.allows(try request(["old.test"])))
        let next = try gate.open(scope(["new.test"]))
        gate.close(token)
        #expect(gate.allows(try request(["new.test"])))
        gate.close(next)
    }

    private func reply(_ responder: ConsentResponder, _ data: Data) async -> Int32 {
        await withCheckedContinuation { continuation in
            responder.changeTrust(data) { continuation.resume(returning: $0) }
        }
    }

    @Test func theResponderRefusesWithoutScopeOrWithBadInput() async throws {
        let settings = RecordingTrustSettings()
        let gate = ConsentGate()
        let responder = ConsentResponder(gate: gate, settings: settings)
        let valid = try HelperWireProtocol.encode(request(["old.test"]))
        #expect(await reply(responder, valid) == errSecAuthFailed)
        let token = try gate.open(scope())
        defer { gate.close(token) }
        #expect(await reply(responder, Data("{".utf8)) == errSecAuthFailed)
        #expect(await reply(responder, Data(count: 131_072)) == errSecAuthFailed)
        #expect(await reply(responder, try HelperWireProtocol.encode(request(["other.test"]))) == errSecAuthFailed)
        #expect(settings.calls.withLock { $0 }.isEmpty)
    }

    @Test func theResponderAppliesAllowedChangesAndMapsStatus() async throws {
        let settings = RecordingTrustSettings()
        let gate = ConsentGate()
        let responder = ConsentResponder(gate: gate, settings: settings)
        let token = try gate.open(scope())
        defer { gate.close(token) }
        #expect(await reply(responder, try HelperWireProtocol.encode(request(["old.test"]))) == errSecSuccess)
        #expect(await reply(responder, try HelperWireProtocol.encode(request(nil))) == errSecSuccess)
        #expect(settings.calls.withLock { $0 } == ["set serverTLS", "remove"])
        let missing = RecordingTrustSettings(status: errSecItemNotFound)
        #expect(ConsentResponder.apply(try request(nil), with: missing) == errSecSuccess)
        let denied = RecordingTrustSettings(status: errSecAuthFailed)
        #expect(ConsentResponder.apply(try request(["old.test"]), with: denied) == errSecAuthFailed)
    }

    @Test func invalidHostnamesOrBytesAreRefusedBeforeSecurityRuns() throws {
        let settings = RecordingTrustSettings()
        let bad = TrustConsentRequest(
            certificateDER: try Fixture.certificate(), hostnames: ["Bad Host"], policy: .serverTLS)
        #expect(ConsentResponder.apply(bad, with: settings) == errSecParam)
        let garbage = TrustConsentRequest(certificateDER: Data("x".utf8), hostnames: nil, policy: .hostnames)
        #expect(ConsentResponder.apply(garbage, with: settings) == errSecAuthFailed)
        #expect(settings.calls.withLock { $0 }.isEmpty)
    }
}
