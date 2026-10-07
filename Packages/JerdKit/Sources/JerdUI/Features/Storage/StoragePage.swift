import JerdDesign
import SwiftUI

/// The detail of the Storage section: the selected bucket, or the storage service overview.
/// Both pages hold the storage controls in their header. It owns the sheets and the RustFS install
/// confirmation.
struct StoragePage: View {
    let state: AppState
    let model: StorageModel
    @Environment(\.isQuitting) private var isQuitting

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
        .confirmationDialog(
            model.pendingRuntimeInstall.map(StorageRuntimeCopy.confirmationTitle) ?? "",
            isPresented: isConfirmingInstall, titleVisibility: .visible, presenting: model.pendingRuntimeInstall
        ) { request in
            Button(StorageRuntimeCopy.confirmTitle(request)) { model.confirmRuntimeInstall() }
                .disabled(isQuitting)
            Button("Cancel", role: .cancel) { model.pendingRuntimeInstall = nil }
        } message: { request in
            Text(StorageRuntimeCopy.confirmationMessage(request))
        }
    }

    private var isConfirmingInstall: Binding<Bool> {
        Binding {
            model.pendingRuntimeInstall != nil
        } set: { isPresented in
            if !isPresented { model.pendingRuntimeInstall = nil }
        }
    }
}
