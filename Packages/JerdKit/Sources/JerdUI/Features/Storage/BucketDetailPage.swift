import JerdDesign
import JerdStorage
import SwiftUI

/// One bucket: its status, connection, access, and Laravel settings, with the storage controls
/// in the header.
struct BucketDetailPage: View {
    let model: StorageModel
    let bucket: StorageBucket

    var body: some View {
        let actions = StorageHeaderActions(model: model)
        FormPage {
            PageHeader(
                bucket.name, subtitle: subtitle, status: NamedStatus("Bucket status", status.displayStatus),
                primaryAction: actions.primary, secondaryActions: actions.secondary
            ) {
                if model.operation.isWorking {
                    BusyIndicator(model.operation.workingMessage ?? "Working…")
                }
            }
        } messages: {
            StoragePageMessages(model: model)
            bucketMessage
        } content: {
            StorageConnectionSection(model: model, bucket: bucket)
            BucketAccessSection(model: model, bucket: bucket)
            StorageFilesSection(model: model)
            StorageServiceSection(model: model)
        }
    }

    private var status: BucketStatus { model.snapshot.status(of: bucket) }

    private var subtitle: String {
        "S3 bucket · RustFS \(model.settings.runtime?.version ?? "not installed")"
    }

    @ViewBuilder private var bucketMessage: some View {
        switch status {
        case .setupIncomplete:
            InlineMessage(
                "The bucket setup did not finish. Retry to create it, apply its access, and check it.", kind: .warning,
                style: .banner,
                action: PageAction(
                    "Retry Setup", isEnabled: model.canChange && model.hasRuntime, identifier: "bucket.retry"
                ) {
                    model.retry(bucket)
                }, identifier: "bucket.incomplete")
        case .missing:
            InlineMessage(
                "This bucket is no longer in storage. Its saved settings remain here. Check the console before you create another bucket.",
                kind: .warning, style: .banner, identifier: "bucket.missing")
        case .ready, .serviceNotRunning:
            EmptyView()
        }
    }
}
