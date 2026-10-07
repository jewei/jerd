import JerdSnapshotSupport
import JerdUIFixtures

extension SnapshotCatalog {
    /// Every snapshot of Jerd. Register each page with one `add` line, for example:
    ///
    ///     catalog.add("sites-running") { JerdWorkspace(state: fixture.state) }
    ///
    /// Page entries use both window sizes and the full window with its toolbar by default.
    /// The pages come from the fixture scenarios (`FixtureScenario` in JerdUIFixtures).
    static var jerd: SnapshotCatalog {
        var catalog = SnapshotCatalog()
        catalog.addComponentGallery()
        catalog.addJerdPages()
        catalog.addServicePages()
        return catalog
    }
}
