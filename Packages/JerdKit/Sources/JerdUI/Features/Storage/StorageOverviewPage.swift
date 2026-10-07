import JerdDesign
import SwiftUI

/// The Storage page when no bucket is selected: the service, its buckets, and its credentials.
struct StorageOverviewPage: View {
    let model: StorageModel
    @Environment(\.isQuitting) private var isQuitting

    var body: some View {
        let actions = StorageHeaderActions(model: model, isQuitting: isQuitting)
        FormPage {
            PageHeader(
                "Storage", subtitle: "S3 buckets on this Mac for your applications' uploads and files.",
                status: NamedStatus("Storage status", model.status), primaryAction: actions.primary,
                secondaryActions: actions.secondary
            ) {
                if model.operation.isWorking {
                    BusyIndicator(model.operation.workingMessage ?? "Working…")
                }
            }
        } messages: {
            StoragePageMessages(model: model)
        } content: {
            if model.loadState.isLoaded, !model.hasRuntime,
                model.runtimeOffer != nil || model.runtimeInstallation != nil
            {
                ServiceRuntimeSection(model: model)
            }
            bucketsSection
            StorageConnectionSection(model: model, bucket: nil)
            StorageCredentialsSection(model: model)
            StorageFilesSection(model: model)
            StorageServiceSection(model: model)
        }
    }

    private var bucketsSection: some View {
        Section {
            ActionRow(bucketTitle, detail: bucketDetail) {
                Button("Add Bucket…") { model.beginAddBucket() }
                    .disabled(isQuitting || !model.canAddBucket)
                    .accessibilityIdentifier("storage.add-bucket")
            }
        } header: {
            Text("Buckets")
        }
    }

    private var bucketTitle: String {
        switch model.buckets.count {
        case 0: "No buckets yet"
        case 1: "1 bucket"
        default: "\(model.buckets.count) buckets"
        }
    }

    private var bucketDetail: String {
        if model.startInstallsRuntime, model.buckets.isEmpty {
            return "Install RustFS first. Then give your application an S3 bucket for uploads and files."
        }
        return model.buckets.isEmpty
            ? "Give your application an S3 bucket for uploads and files. Jerd starts storage and checks the bucket when you create it."
            : "Select a bucket in the sidebar to see its connection and access settings."
    }
}
