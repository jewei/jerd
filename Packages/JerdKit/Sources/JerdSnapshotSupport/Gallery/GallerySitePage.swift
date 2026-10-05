import JerdDesign
import SwiftUI

/// A sample site page built only from design components, as a feature page would be.
struct GallerySitePage: View {
    var body: some View {
        FormPage {
            PageHeader(
                "Studio", subtitle: "https://studio.test",
                status: NamedStatus("Site status", DisplayStatus("Ready", tone: .ready)),
                primaryAction: PageAction(
                    "Open in Browser", systemImage: "safari", identifier: "site.open", perform: GallerySamples.noAction),
                secondaryActions: [
                    PageAction(
                        "Stop", systemImage: "stop.fill", identifier: "site.stop", perform: GallerySamples.noAction)
                ])
        } messages: {
            InlineMessage(
                "The site stopped because PHP-FPM exited. Check the web log.", kind: .error, style: .banner,
                action: PageAction("Open Log", perform: GallerySamples.noAction), identifier: "site.error",
                dismiss: GallerySamples.noAction)
        } content: {
            Section {
                PathRow("Project", path: "/Users/developer/Projects/studio", reveal: GallerySamples.noAction)
                PathRow(
                    "Document root", path: "/Users/developer/Projects/studio/public", reveal: GallerySamples.noAction)
                ValueRow("PHP", value: "Follow default: PHP 8.5.0")
                ValueRow("URL", value: "https://studio.test", isCode: true, copy: GallerySamples.noAction)
            } header: {
                Text("Project")
            } footer: {
                FormFooter("Start adds this site to the running sites. Stop removes only this site.")
            }
            Section("Logs") {
                ActionRow("Web log", detail: "Requests and PHP errors for this site.") {
                    Button("Open Log", systemImage: "doc.text", action: GallerySamples.noAction)
                }
            }
        }
    }
}
