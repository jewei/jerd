import SwiftUI

/// The confirm button of a `SheetScaffold`. A destructive confirm is a plain push button with
/// the system label color: red text on a gray bezel is hard to read (1.7:1 in dark mode). The
/// title, the destructive role, and the missing Return shortcut show the risk.
struct SheetConfirmButton: View {
    let confirmation: SheetConfirmation
    let isEnabled: Bool

    var body: some View {
        let button = Button(confirmation.title, role: confirmation.isDestructive ? .destructive : nil) {
            confirmation.perform()
        }
        .disabled(!isEnabled)
        .accessibilityIdentifier(ifPresent: confirmation.confirmIdentifier)
        if confirmation.usesReturnKey {
            button
                .keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }
}
