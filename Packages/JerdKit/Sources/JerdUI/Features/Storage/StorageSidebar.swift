import JerdDesign
import SwiftUI

/// The Storage sidebar: the registered buckets with their status, and the Add Bucket footer.
struct StorageSidebar: View {
    let state: AppState
    let model: StorageModel

    var body: some View {
        List(selection: state.sidebarSelection(in: .storage)) {
            Section("Buckets") {
                ForEach(model.buckets) { bucket in
                    SidebarRow(
                        bucket.name, subtitle: bucket.publicRead ? "Public read" : "Private",
                        status: model.snapshot.status(of: bucket).displayStatus
                    )
                    .tag(SidebarSelection.bucket(bucket.name))
                    .accessibilityIdentifier(AccessibilityIdentifier.make("sidebar", "bucket", bucket.name))
                }
                if model.buckets.isEmpty {
                    SidebarPlaceholder(
                        SidebarPlaceholder.text(for: model.loadState, items: "buckets", settings: "Storage"))
                }
            }
        }
        .listStyle(.sidebar)
        .sidebarFooter {
            StorageSidebarFooter(model: model)
        }
    }
}
