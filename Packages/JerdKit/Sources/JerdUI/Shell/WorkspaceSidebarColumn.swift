import SwiftUI

/// The sidebar column of the main window, ready to host in its own view: it sets the window
/// values that it needs itself, because a hosting controller does not inherit the environment.
public struct WorkspaceSidebarColumn: View {
    let state: AppState

    public var body: some View {
        WorkspaceSidebar(state: state)
            // The split draws the sidebar material from the top edge to the bottom edge.
            .scrollContentBackground(.hidden)
            .environment(\.isQuitting, state.isQuitting)
    }
}
