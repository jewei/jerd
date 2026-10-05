import JerdDesign
import SwiftUI

/// Gallery page: a standard editor sheet while it waits for work.
struct GallerySheetPage: View {
    @State private var name = "Studio"
    @State private var hostname = "studio"
    @State private var runtime = "default"

    var body: some View {
        SheetScaffold(
            "Edit Site", message: "Jerd serves the document root over HTTPS at the .test address.",
            confirmation: SheetConfirmation("Save", perform: GallerySamples.noAction),
            workingMessage: "Checking the project folder…", cancel: GallerySamples.noAction
        ) {
            Section {
                TextField("Name", text: $name)
                TextField("Address", text: $hostname, prompt: Text("site"))
                Picker("PHP", selection: $runtime) {
                    Text("Follow default: PHP 8.5.0").tag("default")
                    Text("PHP 8.4.12").tag("8.4")
                }
            }
            Section {
                PathRow("Project", path: "/Users/developer/Projects/studio", revealTitle: "Choose…") {}
                InlineMessage("The address studio.test is already in use by another site.", kind: .error)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
