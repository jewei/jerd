import Foundation
import JerdFoundation
import Security
import Testing

@testable import JerdSystem

/// Real XPC in this process: the new client against a declaration of the old helper protocol.
/// It proves the wire compatibility and the descriptor transfer without signing (see `check-xpc`
/// in the README for the signed check).
@Suite struct XPCInteropTests {
    private final class AcceptingTrustSettings: TrustSettingsApplying {
        func setAdminTrust(certificateDER: Data, scope: TrustScope) -> OSStatus { errSecSuccess }
        func removeAdminTrust(certificateDER: Data) -> OSStatus { errSecSuccess }
    }

    private func fixture() throws -> (LegacyHelper, HelperClient, LoopbackListenerPair) {
        let pair = try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
        let consent = TrustConsentRequest(
            certificateDER: try Fixture.certificate(), hostnames: ["a.test"], policy: .serverTLS)
        let helper = LegacyHelper(
            pair: pair, status: try Fixture.data("Wire/status-configured.json"),
            consent: try HelperWireProtocol.encode(consent))
        let client = HelperClient(
            registration: FakeDaemonService(.enabled).registration(),
            opener: AnonymousLinkOpener(endpoint: helper.listener.endpoint), trustSettings: AcceptingTrustSettings())
        return (helper, client, pair)
    }

    @Test func theNewClientReadsTheOldHelpersStatusAndErrors() async throws {
        let (helper, client, pair) = try fixture()
        defer { pair.close() }
        let status = try await client.status()
        #expect(status.setup.hostnames == ["blog.test", "shop.test"] && status.setup.isReadyForServing)
        await #expect(throws: JerdError.unavailable("Stop Jerd's environment before removing system setup.")) {
            try await client.removeSetup()
        }
        withExtendedLifetime(helper) {}
    }

    @Test func listenerDescriptorsSurviveTheSendersClose() async throws {
        let (helper, client, pair) = try fixture()
        let expected = try pair.ports()
        let received = try await client.acquireListeners()
        defer { received.close() }
        pair.close()
        #expect(try received.ports() == expected)
        withExtendedLifetime(helper) {}
    }

    @Test func theOldHelpersReverseCallReachesTheConsentGate() async throws {
        let (helper, client, pair) = try fixture()
        defer { pair.close() }
        let certificate = try InstallationCertificate(
            installationID: Fixture.installationID, der: Fixture.certificate())
        try await client.configure(
            hostnames: try ValidatedHostnames(["a.test"]), caCertificate: certificate, policy: .serverTLS)
        await #expect(throws: JerdError.unavailable("Cannot set Jerd certificate trust: OSStatus -25293")) {
            try await client.configure(
                hostnames: try ValidatedHostnames(["b.test"]), caCertificate: certificate, policy: .serverTLS)
        }
        withExtendedLifetime(helper) {}
    }
}
