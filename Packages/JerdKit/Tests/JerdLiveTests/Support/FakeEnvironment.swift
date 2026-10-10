import JerdWeb

@testable import JerdLive

/// The web environment as a set plan and snapshot; Stop is recorded and stops the plan.
actor FakeEnvironment: EnvironmentControlling {
    var current = EnvironmentSnapshot(state: .stopped, siteIDs: [])
    private var plan: ServingPlan?
    let journal: CallJournal?

    init(journal: CallJournal? = nil) {
        self.journal = journal
    }

    /// The run serves `plan`, or nothing for nil.
    func setRunning(_ plan: ServingPlan?) {
        self.plan = plan
        current = EnvironmentSnapshot(state: plan == nil ? .stopped : .running, siteIDs: plan?.siteIDs ?? [])
    }

    func snapshot() -> EnvironmentSnapshot { current }

    func runningPlan() -> ServingPlan? { plan }

    func stop() async {
        setRunning(nil)
        await journal?.record("environment.stop")
    }
}
