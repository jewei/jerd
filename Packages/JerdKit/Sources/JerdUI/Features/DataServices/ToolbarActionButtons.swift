import JerdDesign
import SwiftUI

/// The toolbar items of a service section: icon buttons with a spoken title, a tooltip, and an
/// accessibility identifier, as the shell README asks.
struct ToolbarActionButtons: View {
    let actions: [PageAction]

    var body: some View {
        ForEach(actions.indices, id: \.self) { index in
            let action = actions[index]
            Button(action: action.perform) {
                Label(action.title, systemImage: action.systemImage ?? "questionmark")
            }
            .disabled(!action.isEnabled)
            .help(action.help ?? action.title)
            .accessibilityIdentifier(action.identifier ?? action.title)
        }
    }
}
