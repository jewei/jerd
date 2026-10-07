extension AppState {
    /// The app became active or inactive. `AppActivityMonitor` in JerdLive reports it.
    public func setAppActive(_ isActive: Bool) {
        updateActivity { $0.isActive = isActive }
    }

    /// The main window appeared, closed, or changed its occlusion. The workspace and
    /// `AppActivityMonitor` report it.
    public func setWindowVisible(_ isVisible: Bool) {
        updateActivity { $0.isWindowVisible = isVisible }
    }

    /// The menu bar menu opened or closed. The menu content reports it.
    public func setMenuOpen(_ isOpen: Bool) {
        updateActivity { $0.isMenuOpen = isOpen }
    }

    private func updateActivity(_ change: (inout AppActivity) -> Void) {
        var next = activity
        change(&next)
        guard next != activity else { return }
        activity = next
        for poller in pollers {
            poller.update(activity: next)
        }
    }
}
