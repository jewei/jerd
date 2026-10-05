import SwiftUI

/// Gallery page: value, action, and path rows, system controls, row messages, and footers.
struct GalleryRowsPage: View {
    @State private var startsAtLogin = true
    @State private var runtime = "8.5"

    var body: some View {
        FormPage {
            PageHeader("Rows", subtitle: "Grouped form rows share one text column with the header.")
        } content: {
            valuesSection
            Section("Actions") {
                ActionRow("Test email", detail: "Send a sample message to the local inbox.") {
                    Button("Send Test Email", systemImage: "paperplane", action: GallerySamples.noAction)
                }
                ActionRow("Laravel settings") {
                    Button("Copy", systemImage: "doc.on.doc", action: GallerySamples.noAction)
                    Button("Show", action: GallerySamples.noAction)
                }
                Toggle("Start when Jerd opens", isOn: $startsAtLogin)
                Picker("PHP version", selection: $runtime) {
                    Text("PHP 8.5").tag("8.5")
                    Text("PHP 8.4").tag("8.4")
                }
            }
            Section("Paths") {
                PathRow("Project", path: "/Users/developer/Projects/studio", reveal: GallerySamples.noAction)
                PathRow("Document root", path: GallerySamples.longPath, reveal: GallerySamples.noAction)
            }
            Section("Row messages") {
                ForEach(MessageKind.allCases, id: \.self) { kind in
                    InlineMessage(Self.sampleText(kind), kind: kind)
                }
            }
        }
    }

    private var valuesSection: some View {
        Section {
            ValueRow("Host", value: "127.0.0.1", isCode: true)
            ValueRow("Inbox URL", value: "http://127.0.0.1:8025/", isCode: true, copy: GallerySamples.noAction)
            ValueRow("Authentication", value: "No username or password")
            ValueRow("CA SHA-256", value: String(repeating: "9F:2C:41:7A:", count: 8), isCode: true)
        } header: {
            Text("Values")
        } footer: {
            FormFooter("Available only on this Mac. Messages are captured here; they are not sent to recipients.")
        }
    }

    static func sampleText(_ kind: MessageKind) -> String {
        switch kind {
        case .info: "PHP, Caddy, Composer, and the Laravel installer are installed and managed by Jerd."
        case .success: "Updated to 1.31.3."
        case .warning: "Redis builds need the Xcode command line tools."
        case .error: "The port 5432 is in use by another process. Select a different port."
        }
    }
}
