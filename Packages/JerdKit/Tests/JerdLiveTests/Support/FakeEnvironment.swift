import JerdWeb

@testable import JerdLive

/// The web environment as a set snapshot; Stop is recorded.
actor FakeEnvironment: EnvironmentControlling {
    var current = EnvironmentSnapshot(state: .stopped, siteIDs: [])
    let journal: CallJournal?

    init(journal: CallJournal? = nil) {
        self.journal = journal
    }

    func snapshot() -> EnvironmentSnapshot { current }

    func setSnapshot(_ snapshot: EnvironmentSnapshot) { current = snapshot }

    func stop() async {
        current = EnvironmentSnapshot(state: .stopped, siteIDs: [])
        await journal?.record("environment.stop")
    }
}
