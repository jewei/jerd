import Foundation
import JerdFoundation
import JerdWeb

@testable import JerdLive

/// The system setup gateway with a set status. A removal is recorded.
actor FakeHTTPSSetup: HTTPSSetupControlling {
    var current: Result<HTTPSSetupStatus, JerdError>
    let journal: CallJournal?

    init(_ status: HTTPSSetupStatus = HTTPSSetupStatus(), journal: CallJournal? = nil) {
        current = .success(status)
        self.journal = journal
    }

    var removalFailure: JerdError?

    func fail(_ error: JerdError) { current = .failure(error) }
    func setStatus(_ status: HTTPSSetupStatus) { current = .success(status) }
    func failRemoval(_ error: JerdError) { removalFailure = error }

    func status() throws -> HTTPSSetupStatus { try current.get() }

    func prepareCAMigration() async throws -> InstallationAuthority {
        await journal?.record("gateway.prepareCAMigration")
        return InstallationAuthority(installationID: UUID(), fingerprint: String(repeating: "b", count: 64))
    }

    func migrateCA() async throws {
        await journal?.record("gateway.migrateCA")
    }

    func removeSetup() async throws {
        await journal?.record("gateway.removeSetup")
        if let removalFailure { throw removalFailure }
        current = .success(HTTPSSetupStatus())
    }
}
