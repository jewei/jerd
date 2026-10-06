import SwiftUI

/// The presentation bindings of every sheet. AppKit can end a sheet without its buttons, for
/// example when Quit ends every open sheet before the staged quit. SwiftUI then sets the
/// binding to nil or false, and the sheet must end exactly as its Cancel ends it: the draft
/// goes, a typed token is cleared, and a waiting HTTPS approval is discarded. So the setter
/// never writes the model; it only runs the sheet's own dismissal.
enum SheetBinding {
    /// For `.sheet(item:)`: a dismissal by SwiftUI runs `dismiss`. A programmatic change of the
    /// item, for example from the retained list to the restore editor, never reaches it.
    @MainActor
    static func item<Item>(
        _ item: @escaping @MainActor () -> Item?, dismiss: @escaping @MainActor () -> Void
    ) -> Binding<Item?> {
        Binding {
            item()
        } set: { next in
            if next == nil { dismiss() }
        }
    }

    /// For `.sheet(isPresented:)`: a dismissal by SwiftUI runs `dismiss`.
    @MainActor
    static func isPresented(
        _ isPresented: @escaping @MainActor () -> Bool, dismiss: @escaping @MainActor () -> Void
    ) -> Binding<Bool> {
        Binding {
            isPresented()
        } set: { next in
            if !next { dismiss() }
        }
    }
}
