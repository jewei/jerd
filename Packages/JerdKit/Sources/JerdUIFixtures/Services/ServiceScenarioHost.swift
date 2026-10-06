/// Keeps the fixture of one service scenario for all renderings, and prepares it once.
@MainActor
public final class ServiceScenarioHost {
    public let scenario: ServiceScenario
    private var storedFixture: AppFixture?
    private var hasStartedPreparation = false

    public nonisolated init(_ scenario: ServiceScenario) {
        self.scenario = scenario
    }

    public var fixture: AppFixture {
        if let storedFixture { return storedFixture }
        let fixture = scenario.makeFixture()
        storedFixture = fixture
        return fixture
    }

    public func prepare() async {
        guard !hasStartedPreparation else { return }
        hasStartedPreparation = true
        await scenario.prepare(fixture)
    }

    public var isReady: Bool {
        storedFixture.map(scenario.isReady) ?? false
    }
}
