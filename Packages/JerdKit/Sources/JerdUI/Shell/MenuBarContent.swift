import SwiftUI

/// The content of the menu bar extra, in the default menu style. The app target puts it in a
/// `MenuBarExtra` whose `isInserted` follows `AppearanceModel.showMenuBar`.
public struct MenuBarContent: View {
    let state: AppState
    let quit: @MainActor () -> Void

    /// - Parameter quit: Terminates the app (`NSApp.terminate`), which runs the staged quit.
    public init(state: AppState, quit: @escaping @MainActor () -> Void) {
        self.state = state
        self.quit = quit
    }

    public var body: some View {
        ForEach(MenuBarMenu.items(for: state, quit: quit)) { item in
            MenuBarItemView(item: item)
        }
        .onAppear { state.setMenuOpen(true) }
        .onDisappear { state.setMenuOpen(false) }
    }
}
