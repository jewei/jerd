import JerdDesign
import SwiftUI

/// The detail of the Storage section: the selected bucket, or the storage service overview.
/// Both pages hold the storage controls in their header.
struct StoragePage: View {
    let state: AppState
    let model: StorageModel

    var body: some View {
        Group {
            if case .bucket(let name) = state.navigation.selection(in: .storage), let bucket = model.bucket(named: name)
            {
                BucketDetailPage(model: model, bucket: bucket)
            } else {
                StorageOverviewPage(model: model)
            }
        }
        .sheet(isPresented: SheetBinding.isPresented({ model.bucketDraft != nil }, dismiss: model.cancelAddBucket)) {
            AddBucketSheet(model: model)
        }
        .sheet(isPresented: SheetBinding.isPresented({ model.portsDraft != nil }, dismiss: model.cancelPorts)) {
            StoragePortsSheet(model: model)
        }
    }
}
