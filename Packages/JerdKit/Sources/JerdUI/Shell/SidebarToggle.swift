import SwiftUI

/// The toolbar button that shows or hides the sidebar of the current section. It
/// replaces the system toggle, which `toolbar(removing:)` does not hide for one section only:
/// Mail has no sidebar, so there the button is off and says why.
struct SidebarToggle: View {
    let state: AppState

    var body: some View {
        Button {
            state.navigation.toggleSidebar()
        } label: {
            Label(Self.title(for: state.navigation), systemImage: "sidebar.left")
        }
        .disabled(!state.navigation.canToggleSidebar)
        .help(Self.help(for: state.navigation))
        .accessibilityIdentifier("workspace.toggle-sidebar")
    }

    /// The title and spoken name: what the button does now.
    static func title(for navigation: NavigationState) -> String {
        navigation.isSidebarVisible(in: navigation.section) ? "Hide Sidebar" : "Show Sidebar"
    }

    /// The tooltip. On Mail it explains why the button is off.
    static func help(for navigation: NavigationState) -> String {
        navigation.canToggleSidebar ? "\(title(for: navigation)) (⌃⌘S)" : "Mail has no sidebar"
    }
}
