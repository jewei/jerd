/// What the user can see of Jerd now. Polling is fast only while state is on screen.
public struct AppActivity: Equatable, Sendable {
    /// Jerd is the active application.
    public var isActive: Bool
    /// The main window is open and not minimized.
    public var isWindowVisible: Bool
    /// The menu bar menu is open.
    public var isMenuOpen: Bool

    public init(isActive: Bool = false, isWindowVisible: Bool = false, isMenuOpen: Bool = false) {
        self.isActive = isActive
        self.isWindowVisible = isWindowVisible
        self.isMenuOpen = isMenuOpen
    }

    /// True when the user can see live state: an open menu, or the window of the active app.
    public var showsLiveState: Bool {
        isMenuOpen || (isActive && isWindowVisible)
    }
}
