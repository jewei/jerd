import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct SystemTrustProbeTests {
    static func probe(_ addresses: [String]?, status: Int = 200, body: String = "Jerd is ready.") -> SystemTrustProbe {
        SystemTrustProbe(resolve: { _ in addresses }, fetch: { _ in (status, Data(body.utf8)) })
    }

    @Test func aLoopbackHostWithTheReadyAnswerPasses() async throws {
        try await Self.probe(["127.0.0.1", "127.0.0.1"]).check(hostname: "Demo.test")
    }

    @Test func anUnresolvedHostAsksForARetry() async {
        for addresses in [nil, [String]()] {
            await #expect(
                throws: JerdError.unavailable(
                    "The hostname does not resolve yet. Retry Start after macOS updates its host cache.")
            ) { try await Self.probe(addresses).check(hostname: "demo.test") }
        }
    }

    @Test(arguments: [["::1"], ["127.0.0.1", "::1"], ["10.0.0.1"], ["127.0.0.2"]])
    func anyOtherAddressIsRefused(_ addresses: [String]) async {
        await #expect(throws: JerdError.unavailable("The hostname must resolve only to 127.0.0.1.")) {
            try await Self.probe(addresses).check(hostname: "demo.test")
        }
    }

    @Test(arguments: [(200, "other"), (404, "Jerd is ready."), (302, "")])
    func anotherAnswerIsRefused(_ status: Int, _ body: String) async {
        await #expect(throws: JerdError.unavailable("The system HTTPS check did not receive Jerd's response.")) {
            try await Self.probe(["127.0.0.1"], status: status, body: body).check(hostname: "demo.test")
        }
    }

    @Test func theRequestUsesTheReadinessPathAndAnInvalidHostnameIsRefused() async throws {
        let probe = SystemTrustProbe(
            resolve: { _ in ["127.0.0.1"] },
            fetch: { url in
                #expect(url.absoluteString == "https://demo.test/.jerd/ready")
                return (200, Data("Jerd is ready.".utf8))
            })
        try await probe.check(hostname: "demo.test")
        await #expect(throws: JerdError.self) { try await probe.check(hostname: "demo.com") }
    }

    @Test func theSystemResolverReadsLocalhost() {
        #expect(SystemTrustProbe.systemResolve("localhost")?.contains("127.0.0.1") == true)
    }
}

@Suite struct ApprovalPredicateTests {
    @Test func approvalNeedsHostsTrustServerPolicyNoRecoveryAndEveryHostname() throws {
        let approved = try FakeSystem.approved(["a.test", "b.test"])
        #expect(ApprovalPredicate.covers(approved, hostnames: ["b.test"]))
        #expect(ApprovalPredicate.covers(approved, hostnames: []))
        #expect(!ApprovalPredicate.covers(approved, hostnames: ["a.test", "c.test"]))
        var changed = approved
        changed.trustPolicy = .hostnames
        #expect(!ApprovalPredicate.covers(changed, hostnames: ["a.test"]))
        for flag in [\HTTPSSetupStatus.hostsConfigured, \.trustConfigured] {
            changed = approved
            changed[keyPath: flag] = false
            #expect(!ApprovalPredicate.covers(changed, hostnames: ["a.test"]))
        }
        changed = approved
        changed.hasPendingRecovery = true
        #expect(!ApprovalPredicate.covers(changed, hostnames: ["a.test"]))
    }

    @Test func theCAMatchesByInstallationAndFingerprint() throws {
        let approved = try FakeSystem.approved(["a.test"])
        let fingerprint = try Certificates.authority().fingerprint
        #expect(
            ApprovalPredicate.matches(approved, installationID: Certificates.installationID, fingerprint: fingerprint))
        #expect(!ApprovalPredicate.matches(approved, installationID: UUID(), fingerprint: fingerprint))
        #expect(!ApprovalPredicate.matches(approved, installationID: Certificates.installationID, fingerprint: "00"))
    }

    @Test func aStatusWithoutCertificateOrHostnamesHasNoRegistration() throws {
        #expect(HTTPSSetupStatus().registration == nil)
        #expect(try FakeSystem.approved(["a.test"]).registration?.hostnames == ["a.test"])
    }
}
