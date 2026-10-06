import JerdDesign
import SwiftUI

/// The Files section of a service page: the data folder with Show in Finder, and the log.
struct ServiceFilesSection: View {
    /// The words of one service's Files section.
    struct Copy {
        var dataLabel = "Data folder"
        /// The log in a spoken name, for example "mail log".
        let logSubject: String
        let missingData: String
        let missingLog: String
        let footer: String
    }

    let files: ServiceFiles?
    let copy: Copy
    let reveal: @MainActor () -> Void
    let openLog: @MainActor () -> Void

    var body: some View {
        Section {
            if let files, files.hasDataFolder {
                PathRow(copy.dataLabel, path: files.dataFolder.path, reveal: reveal)
            } else {
                ActionRow(copy.dataLabel, detail: copy.missingData) {}
            }
            ActionRow("Log", detail: files?.hasLog == true ? nil : copy.missingLog) {
                Button("Open Log", action: openLog)
                    .disabled(files?.hasLog != true)
                    .accessibilityLabel("Open \(copy.logSubject)")
                    .accessibilityIdentifier(AccessibilityIdentifier.make("open", copy.logSubject))
            }
        } header: {
            Text("Files")
        } footer: {
            FormFooter(copy.footer)
        }
    }
}
