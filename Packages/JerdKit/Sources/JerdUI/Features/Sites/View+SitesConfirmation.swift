import SwiftUI

extension View {
    /// The confirmation dialog of the Sites model. Destructive steps never confirm with Return.
    func sitesConfirmation(_ model: SitesModel) -> some View {
        confirmationDialog(
            model.confirmation?.title ?? "",
            isPresented: Binding {
                model.confirmation != nil
            } set: { isPresented in
                if !isPresented { model.confirmation = nil }
            },
            titleVisibility: .visible, presenting: model.confirmation
        ) { step in
            Button(step.confirmTitle, role: step.isDestructive ? .destructive : nil) { model.confirm() }
                .keyboardShortcut(step.isDestructive ? nil : .defaultAction)
            Button("Cancel", role: .cancel) {}
        } message: { step in
            Text(step.message)
        }
    }
}
