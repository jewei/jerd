import SwiftUI

extension View {
    /// Adds ⌘N for the Add action of a section. Only the sidebar of the current section is in
    /// the window, so the shortcut always belongs to the section that the user sees.
    func addShortcut(_ title: String, isEnabled: Bool, perform: @escaping @MainActor () -> Void) -> some View {
        background {
            Button(title, action: perform)
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!isEnabled)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
