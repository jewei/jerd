import SwiftUI

extension View {
    /// The tunnel editor and the tunnel log sheet.
    func tunnelSheets(_ model: TunnelsModel) -> some View {
        sheet(
            item: Binding {
                model.sheet
            } set: { sheet in
                if sheet == nil { model.cancelEditor() }
            }
        ) { sheet in
            switch sheet {
            case .editor(let editor): TunnelEditorSheet(model: model, editor: editor)
            case .log(let log): TunnelLogSheet(model: model, log: log)
            }
        }
    }

    /// The Connect and Remove confirmations. Remove never confirms with Return.
    func tunnelConfirmation(_ model: TunnelsModel) -> some View {
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
