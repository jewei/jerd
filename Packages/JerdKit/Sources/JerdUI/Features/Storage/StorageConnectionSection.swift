import JerdDesign
import JerdStorage
import SwiftUI

/// The S3 connection values. With a bucket it also names the bucket.
struct StorageConnectionSection: View {
    let model: StorageModel
    let bucket: StorageBucket?

    var body: some View {
        Section {
            ValueRow("Endpoint", value: model.settings.endpoint, isCode: true, copy: model.copyEndpoint)
            if let bucket {
                ValueRow("Bucket", value: bucket.name, isCode: true)
            }
            ValueRow("Region", value: StorageSettings.region, isCode: true)
            ValueRow("Addressing", value: "Path style")
        } header: {
            Text("Connection")
        } footer: {
            FormFooter("Available only on this Mac. All buckets use the same storage service.")
        }
    }
}
