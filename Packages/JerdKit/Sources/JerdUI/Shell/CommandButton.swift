import SwiftUI

/// The menu item of one `AppCommand`.
struct CommandButton: View {
    let command: AppCommand
    let state: AppState

    var body: some View {
        let button = Button(command.title(in: state)) {
            command.perform(in: state)
        }
        .disabled(!command.isEnabled(in: state))
        if let shortcut = command.shortcut {
            button.keyboardShortcut(shortcut.keyboardShortcut)
        } else {
            button
        }
    }
}
