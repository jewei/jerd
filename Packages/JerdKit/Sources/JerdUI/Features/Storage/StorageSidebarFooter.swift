import JerdDesign
import SwiftUI

/// The footer of the Storage sidebar: Add Bucket and the bucket count. File › New Bucket… (⌘N)
/// is the section's `newItemAction`.
struct StorageSidebarFooter: View {
    let model: StorageModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        SidebarFooter(
            addTitle: "Add Bucket", caption: caption,
            action: {
                model.beginAddBucket()
            }
        )
        .disabled(isQuitting || !model.canAddBucket)
    }

    private var caption: String {
        model.buckets.count == 1 ? "1 bucket" : "\(model.buckets.count) buckets"
    }
}
