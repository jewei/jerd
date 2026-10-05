import JerdSnapshotSupport

extension SnapshotCatalog {
    /// Every snapshot of Jerd. Register each page with one `add` line, for example:
    ///
    ///     catalog.add("sites-running") { WorkspaceView(model: .sitesRunning) }
    ///
    /// Page entries use both window sizes and the full window with its toolbar by default.
    static var jerd: SnapshotCatalog {
        var catalog = SnapshotCatalog()
        catalog.addComponentGallery()
        return catalog
    }
}
