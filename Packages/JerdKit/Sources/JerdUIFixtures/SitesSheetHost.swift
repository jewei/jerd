/// Keeps the fixture of one sheet scenario for all renderings of its snapshot entry, and
/// prepares it once.
@MainActor
final class SitesSheetHost {
    let scenario: SitesSheetScenario
    private var storedFixture: AppFixture?
    private var hasStartedPreparation = false

    nonisolated init(_ scenario: SitesSheetScenario) {
        self.scenario = scenario
    }

    var fixture: AppFixture {
        if let storedFixture { return storedFixture }
        let fixture = scenario.makeFixture()
        storedFixture = fixture
        return fixture
    }

    func prepare() async {
        guard !hasStartedPreparation else { return }
        hasStartedPreparation = true
        await scenario.prepare(fixture)
    }

    var isReady: Bool {
        storedFixture.map(scenario.isReady) ?? false
    }
}
