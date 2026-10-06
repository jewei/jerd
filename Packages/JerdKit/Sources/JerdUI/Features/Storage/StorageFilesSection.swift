import SwiftUI

/// The storage data folder and log.
struct StorageFilesSection: View {
    let model: StorageModel

    var body: some View {
        ServiceFilesSection(
            files: model.files,
            copy: .init(
                logSubject: "storage log", missingData: "Start storage once to create its data folder.",
                missingLog: "The storage log is not available yet.",
                footer: "Buckets, objects, and credentials remain after Stop or Quit."),
            reveal: model.revealData, openLog: model.openLog)
    }
}
