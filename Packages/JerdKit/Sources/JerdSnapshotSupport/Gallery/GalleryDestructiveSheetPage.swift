import JerdDesign
import SwiftUI

/// Gallery page: a compact sheet that confirms a destructive action.
struct GalleryDestructiveSheetPage: View {
    var body: some View {
        SheetScaffold(
            "Delete This Retained Backup?",
            message: "This removes only the selected backup. It cannot be undone. Current service data stays in place.",
            size: .compact,
            confirmation: SheetConfirmation("Delete Backup", isDestructive: true, perform: GallerySamples.noAction),
            cancel: GallerySamples.noAction
        ) {
            Section {
                ValueRow("Service", value: "Mail")
                ValueRow("Size", value: "48.2 MB")
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
