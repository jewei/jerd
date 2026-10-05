import SwiftUI

/// Draws a `PageAction` as a regular or primary button.
struct PageActionButton: View {
    let action: PageAction
    let isPrimary: Bool

    var body: some View {
        Button(role: action.role) {
            action.perform()
        } label: {
            if let systemImage = action.systemImage {
                Label(action.title, systemImage: systemImage)
            } else {
                Text(action.title)
            }
        }
        .primaryActionStyle(isPrimary: isPrimary, isEnabled: action.isEnabled)
        .help(action.help ?? action.title)
        .accessibilityLabel(action.accessibilityLabel ?? action.title)
    }
}
