import Foundation
import JerdFoundation
import Testing

@testable import JerdSystem

/// The JSON fixtures in `Fixtures/Wire` were written by the old `JerdCore` types with `JSONEncoder()`.
@Suite struct WireDTOTests {
    private func object(_ data: Data) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }

    /// Decodes the old JSON, encodes it again, and requires the same JSON object (key order is free).
    private func roundTrip<Value: Codable & Equatable>(_ type: Value.Type, _ name: String) throws -> Value {
        let golden = try Fixture.data("Wire/\(name).json")
        let value = try JSONDecoder().decode(type, from: golden)
        #expect(try object(HelperWireProtocol.encode(value)) == object(golden))
        return value
    }

    @Test func registrationRequestKeepsItsKeys() throws {
        let request = try roundTrip(SystemRegistrationRequest.self, "request")
        #expect(request.installationID == Fixture.installationID)
        #expect(request.hostnames == ["blog.test", "shop.test"])
        #expect(request.certificateDER == (try Fixture.certificate()))
        #expect(request.trustPolicy == .serverTLS)
    }

    @Test func registrationRequestRequiresEveryKey() throws {
        let json =
            #"{"installationID":"6BA7B810-9DAD-11D1-80B4-00C04FD430C8","hostnames":["a.test"],"certificateDER":"AA=="}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SystemRegistrationRequest.self, from: Data(json.utf8))
        }
    }

    @Test(arguments: ["status-empty", "status-configured", "status-recovery"])
    func statusFromAnOldHelperDecodesAndEncodesTheSameKeys(name: String) throws {
        let status = try roundTrip(SystemSetupStatus.self, name)
        #expect(status.operationInProgress == nil)
    }

    @Test func recoveryStatusKeepsEveryField() throws {
        let status = try roundTrip(SystemSetupStatus.self, "status-recovery")
        let recovery = try #require(status.recovery)
        #expect(recovery.operation == "Configure HTTPS")
        #expect(recovery.canRestore && recovery.canRemove)
        #expect(recovery.installationID == Fixture.installationID)
        #expect(recovery.fingerprint == FileDigest.hexSHA256(of: try Fixture.certificate()))
        #expect(recovery.policies == [.serverTLS])
    }

    /// Regression test: an old app decodes the report of an unreadable record and shows it with both
    /// actions disabled, and the new app reads the placeholders as nil again.
    @Test func anUnreadableRecoveryReportDecodesInAnOldApp() throws {
        let report = RecoveryAssessor.unreadable(
            id: "abc", reason: "The record is damaged.", location: URL(fileURLWithPath: "/tmp/pending.json"))
        let status = SystemSetupStatus(recovery: report)
        let bytes = try HelperWireProtocol.encode(status)
        let old = try #require(try JSONDecoder().decode(LegacySetupStatus.self, from: bytes).recovery)
        #expect(!old.canRestore && !old.canRemove)
        #expect(old.details.first == "The record is damaged.")
        #expect(old.certificateDER.isEmpty)
        let new = try #require(try JSONDecoder().decode(SystemSetupStatus.self, from: bytes).recovery)
        #expect(new == report)
        #expect(new.installationID == nil && new.certificateDER == nil && new.fingerprint == nil)
    }

    @Test func aRecoveryReportWithoutTheIdentityKeysStillDecodes() throws {
        let report = RecoveryAssessor.unreadable(id: "abc", reason: "r", location: URL(fileURLWithPath: "/p"))
        let full = try #require(try object(HelperWireProtocol.encode(report)).mutableCopy() as? NSMutableDictionary)
        full.removeObjects(forKeys: ["installationID", "certificateDER"])
        let decoded = try JSONDecoder().decode(
            SystemRecoveryStatus.self, from: JSONSerialization.data(withJSONObject: full))
        #expect(decoded == report)
    }

    @Test func aNewOptionalStatusFieldIsOmittedWhenNil() throws {
        var status = SystemSetupStatus.empty
        #expect(try object(HelperWireProtocol.encode(status))["operationInProgress"] == nil)
        status.operationInProgress = "Configure HTTPS"
        let decoded = try JSONDecoder().decode(SystemSetupStatus.self, from: HelperWireProtocol.encode(status))
        #expect(decoded.operationInProgress == "Configure HTTPS")
    }

    @Test func approvalAndConsentRequestsKeepTheirKeys() throws {
        let approval = try roundTrip(SystemRecoveryApproval.self, "approval")
        #expect(approval.action == .restorePrevious)
        let install = try roundTrip(TrustConsentRequest.self, "consent-install")
        #expect(install.hostnames == ["shop.test"] && install.policy == .serverTLS)
        let removal = try roundTrip(TrustConsentRequest.self, "consent-remove")
        #expect(removal == TrustConsentRequest.removal(of: try Fixture.certificate()))
        #expect(try object(Fixture.data("Wire/consent-remove.json"))["hostnames"] == nil)
    }

    @Test func enumRawValuesAreStable() {
        #expect(CertificateTrustPolicy.allCases.map(\.rawValue) == ["hostnames", "serverTLS"])
        #expect(SystemRecoveryAction.allCases.map(\.rawValue) == ["restorePrevious", "removeSetup"])
        #expect(CertificateTrustPolicy.hostnames < .serverTLS)
    }

    @Test func readinessNeedsServerTrustAndNoPendingWork() {
        let ready = SystemSetupStatus(hostsConfigured: true, trustConfigured: true, trustPolicy: .serverTLS)
        #expect(ready.isReadyForServing)
        var legacy = ready
        legacy.trustPolicy = .hostnames
        #expect(!legacy.isReadyForServing)
        var running = ready
        running.operationInProgress = "Remove HTTPS"
        #expect(!running.isReadyForServing)
    }
}
