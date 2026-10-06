extension AppState {
    /// The Sites feature and its tunnels, on the ports of `dependencies`.
    static func makeSites(_ dependencies: AppDependencies, clipboard: Clipboard, lock: OperationLock) -> SitesModel {
        let tunnels = TunnelsModel(
            port: dependencies.tunnels, panels: dependencies.filePanels, workspace: dependencies.workspace,
            clipboard: clipboard)
        return SitesModel(
            port: dependencies.sites, tunnels: tunnels, panels: dependencies.filePanels,
            workspace: dependencies.workspace, clipboard: clipboard, lock: lock)
    }

    /// Lets the Sites models navigate, bring the window forward, and show the window alert.
    func connectSitesShell() {
        let shell = SitesShell(
            show: { [weak self] destination in self?.navigation.show(destination) },
            open: { [weak self] destination in self?.open(destination) },
            alert: { [weak self] alert in self?.alert = alert })
        sites.shell = shell
        sites.tunnels.shell = shell
    }
}
