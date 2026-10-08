import Foundation
import Security

@testable import JerdSystem

/// A helper client on fakes for the restart tests: a configured helper, a daemon with the exit
/// race, an opener whose links fail like XPC, and an optional pause that really suspends.
enum RecoveryFixture {
    private final class AcceptingTrustSettings: TrustSettingsApplying {
        func setAdminTrust(certificateDER: Data, scope: TrustScope) -> OSStatus { errSecSuccess }
        func removeAdminTrust(certificateDER: Data) -> OSStatus { errSecSuccess }
    }

    static func configuredHelper() throws -> FakeHelper {
        FakeHelper(
            .init(
                status: SystemSetupStatus(
                    hostnames: ["games-jp.test"], installationID: Fixture.installationID,
                    certificateDER: try Fixture.certificate(), hostsConfigured: true, trustConfigured: true,
                    trustPolicy: .serverTLS)))
    }

    static func client(
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
    static func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    /// Returns once `condition` holds, checking between yields.
    static func until(_ condition: () -> Bool) async {
        while !condition() { await Task.yield() }
    }
}
