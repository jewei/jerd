import JerdDesign
import SwiftUI

/// The footer of the Storage sidebar: Add Bucket (⌘N) and the bucket count.
struct StorageSidebarFooter: View {
    let model: StorageModel

    var body: some View {
        SidebarFooter(
            addTitle: "Add Bucket", caption: caption,
            action: {
                model.beginAddBucket()
            }
        )
        .disabled(!model.canAddBucket)
        .addShortcut("Add Bucket", isEnabled: model.canAddBucket) { model.beginAddBucket() }
    }

    private var caption: String {
        model.buckets.count == 1 ? "1 bucket" : "\(model.buckets.count) buckets"
    }
}
