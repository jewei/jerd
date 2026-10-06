import JerdDesign
import SwiftUI

/// The detail of the Storage section: the selected bucket, or the storage service overview.
/// Both pages hold the storage controls in their header.
struct StoragePage: View {
    let state: AppState
    @Bindable var model: StorageModel

    var body: some View {
        Group {
            if case .bucket(let name) = state.navigation.selection(in: .storage), let bucket = model.bucket(named: name)
            {
                BucketDetailPage(model: model, bucket: bucket)
            } else {
                StorageOverviewPage(model: model)
            }
        }
        .sheet(isPresented: isAddingBucket) {
            AddBucketSheet(model: model)
        }
        .sheet(isPresented: isEditingPorts) {
            StoragePortsSheet(model: model)
        }
    }

    private var isAddingBucket: Binding<Bool> {
        Binding {
            model.bucketDraft != nil
        } set: { isPresented in
            if !isPresented { model.cancelAddBucket() }
        }
    }

    private var isEditingPorts: Binding<Bool> {
        Binding {
            model.portsDraft != nil
        } set: { isPresented in
            if !isPresented { model.cancelPorts() }
        }
    }
}
