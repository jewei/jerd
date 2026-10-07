extension AppState {
    /// The Sites feature and its tunnels, on the ports of `dependencies`. The shell reaches the
    /// app state through `handle`, because `AppState.init` builds the models before `self` exists.
    static func makeSites(
        _ dependencies: AppDependencies, clipboard: Clipboard, lock: OperationLock, handle: AppStateHandle
    ) -> SitesModel {
        let shell = makeSitesShell(handle)
        let tunnels = TunnelsModel(
            port: dependencies.tunnels, panels: dependencies.filePanels, workspace: dependencies.workspace,
            clipboard: clipboard, shell: shell)
        return SitesModel(
            port: dependencies.sites, tunnels: tunnels, panels: dependencies.filePanels,
            workspace: dependencies.workspace, clipboard: clipboard, lock: lock, shell: shell)
    }

    /// Navigation, the window, and the window alert of the Sites models.
    static func makeSitesShell(_ handle: AppStateHandle) -> SitesShell {
        SitesShell(
            show: { destination in handle.state?.navigation.show(destination) },
            open: { destination in handle.state?.open(destination) },
            alert: { alert in handle.state?.alert = alert })
    }
}
