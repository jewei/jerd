import JerdLive
import SwiftUI

extension View {
    /// Hands this scene's `openWindow` action to the presenter, so the menu bar item, the app
    /// menu, and links can open the main window after the user closed it.
    func connectsMainWindow(to presenter: MainWindowPresenter) -> some View {
        modifier(MainWindowConnection(presenter: presenter))
    }
}

/// Reads `openWindow` from the environment, which only a view can do.
private struct MainWindowConnection: ViewModifier {
    let presenter: MainWindowPresenter
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            let openWindow = openWindow
            presenter.connect { openWindow(id: MainWindowPresenter.windowID) }
        }
    }
}
