/// Keeps the fixture of one scenario for all renderings of its snapshot entry, and prepares it
/// once.
@MainActor
public final class ScenarioHost {
    public let scenario: FixtureScenario
    private var storedFixture: AppFixture?
    private var hasStartedPreparation = false

    public nonisolated init(_ scenario: FixtureScenario) {
        self.scenario = scenario
    }

    /// The fixture, built on first use.
    public var fixture: AppFixture {
        if let storedFixture { return storedFixture }
        let fixture = scenario.makeFixture()
        storedFixture = fixture
        return fixture
    }

    /// Runs the scenario steps once; later calls return at once.
    public func prepare() async {
        guard !hasStartedPreparation else { return }
        hasStartedPreparation = true
        await scenario.prepare(fixture)
    }

    public var isReady: Bool {
        storedFixture.map(scenario.isReady) ?? false
    }
}
