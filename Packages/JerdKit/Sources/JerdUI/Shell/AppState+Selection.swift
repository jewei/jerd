import SwiftUI

extension AppState {
    /// The selection binding of a feature sidebar `List`. Tag each row with its
    /// `SidebarSelection`. A native list refresh can report nil or an item of another section;
    /// neither clears the selection that the user made (`NavigationState.select`).
    public func sidebarSelection(in section: AppSection) -> Binding<SidebarSelection?> {
        Binding {
            self.navigation.selection(in: section)
        } set: { selection in
            self.navigation.select(selection)
        }
    }
}
