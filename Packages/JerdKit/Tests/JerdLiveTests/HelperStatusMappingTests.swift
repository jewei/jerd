import Foundation
import JerdFoundation
import JerdSystem
import JerdWeb
import Testing

@testable import JerdLive

@Suite("Helper status mapping")
struct HelperStatusMappingTests {
    static func recovery() throws -> SystemRecoveryStatus {
        SystemRecoveryStatus(
            id: "abc", operation: "Configure HTTPS", phase: "hosts", details: [], canRestore: true, canRemove: true,
            installationID: Fixture.installationID, certificateDER: try Fixture.certificate(),
            previousHostnames: ["old.test"], intendedHostnames: ["new.test"], policies: [.serverTLS])
    }

    @Test func mapsEveryFieldOfAnApprovedSetup() throws {
        let der = try Fixture.certificate()
        let status = HelperStatus(
            availability: .enabled,
            setup: SystemSetupStatus(
                hostnames: ["a.test", "b.test"], installationID: Fixture.installationID, certificateSHA256: "ff",
                certificateDER: der, hostsConfigured: true, trustConfigured: true, trustPolicy: .serverTLS))

        let mapped = try HelperStatusMapping.httpsStatus(status)

        #expect(
            mapped
                == HTTPSSetupStatus(
                    hostnames: ["a.test", "b.test"], installationID: Fixture.installationID, certificateSHA256: "ff",
                    certificateDER: der, hostsConfigured: true, trustConfigured: true, trustPolicy: .serverTLS,
                    hasPendingRecovery: false))
    }

    @Test func aDisabledHelperIsAnEmptySetup() throws {
        let mapped = try HelperStatusMapping.httpsStatus(HelperStatus(availability: .requiresApproval, setup: .empty))
        #expect(mapped == HTTPSSetupStatus())
    }

    @Test func anInterruptedTransactionIsAPendingRecovery() throws {
        let recovery = try Self.recovery()
        let status = HelperStatus(
            availability: .enabled, setup: SystemSetupStatus(hostnames: ["old.test"], recovery: recovery))

        #expect(try HelperStatusMapping.httpsStatus(status).hasPendingRecovery)
        #expect(try HelperStatusMapping.pendingRecovery(status) == recovery)
    }

    @Test func aRunningTransactionIsNeitherNoSetupNorInterrupted() {
        let status = HelperStatus(
            availability: .enabled, setup: SystemSetupStatus(operationInProgress: "Configure HTTPS"))

        #expect(throws: HelperStatusMapping.busyError("Configure HTTPS")) {
            try HelperStatusMapping.httpsStatus(status)
        }
        #expect(throws: HelperStatusMapping.busyError("Configure HTTPS")) {
            try HelperStatusMapping.pendingRecovery(status)
        }
    }

    @Test(arguments: [(CertificateTrustPolicy.hostnames, HTTPSTrustPolicy.hostnames), (.serverTLS, .serverTLS)])
    func trustPoliciesMapBothWays(certificate: CertificateTrustPolicy, https: HTTPSTrustPolicy) {
        #expect(HelperStatusMapping.trustPolicy(certificate) == https)
        #expect(HelperStatusMapping.certificatePolicy(https) == certificate)
    }

    @Test func aRegistrationBecomesAValidatedHelperRequest() throws {
        let registration = HTTPSRegistration(
            installationID: Fixture.installationID, hostnames: ["B.test", "a.test"],
            certificateDER: try Fixture.certificate(), trustPolicy: .serverTLS)

        let request = try HelperStatusMapping.request(for: registration)

        #expect(request.hostnames.values.map(\.value) == ["a.test", "b.test"])
        #expect(request.certificate.installationID == Fixture.installationID)
        #expect(request.policy == .serverTLS)
    }

    @Test func aCertificateOfAnotherInstallationIsRefusedBeforeTheHelper() throws {
        let registration = HTTPSRegistration(
            installationID: UUID(), hostnames: ["a.test"], certificateDER: try Fixture.certificate(),
            trustPolicy: .serverTLS)

        #expect(throws: (any Error).self) { try HelperStatusMapping.request(for: registration) }
    }
}
