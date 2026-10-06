import JerdDesign
import SwiftUI

/// The Storage page when no bucket is selected: the service, its buckets, and its credentials.
struct StorageOverviewPage: View {
    let model: StorageModel

    var body: some View {
        let actions = StorageHeaderActions(model: model)
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
                    .disabled(!model.canAddBucket)
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
        model.buckets.isEmpty
            ? "Give your application an S3 bucket for uploads and files. Jerd starts storage and checks the bucket when you save."
            : "Select a bucket in the sidebar to see its connection and access settings."
    }
}
