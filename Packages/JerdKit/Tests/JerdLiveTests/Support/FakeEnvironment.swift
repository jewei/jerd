import Foundation
import JerdWeb

@testable import JerdLive

/// The web environment as a set snapshot; Stop is recorded.
actor FakeEnvironment: EnvironmentControlling {
    var current = EnvironmentSnapshot(state: .stopped, siteIDs: [])
    let journal: CallJournal?
    private(set) var preparedSites: [UUID] = []
    var preparationFailure: Bool = false

    init(journal: CallJournal? = nil) {
        self.journal = journal
    }

    func snapshot() -> EnvironmentSnapshot { current }

    func setSnapshot(_ snapshot: EnvironmentSnapshot) { current = snapshot }

    func setPreparationFailure() { preparationFailure = true }

    func preparePublicHosts(for siteID: UUID) async throws {
        if preparationFailure { throw CancellationError() }
        preparedSites.append(siteID)
    }

    func stop() async {
        current = EnvironmentSnapshot(state: .stopped, siteIDs: [])
        await journal?.record("environment.stop")
    }
}
