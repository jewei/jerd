import JerdDesign
import JerdStorage
import SwiftUI

/// The S3 connection values. With a bucket it also names the bucket.
struct StorageConnectionSection: View {
    let model: StorageModel
    let bucket: StorageBucket?

    var body: some View {
        Section {
            ForEach(Self.values(model, bucket: bucket)) { ConnectionValueRow(value: $0) }
        } header: {
            Text("Connection")
        } footer: {
            FormFooter("Available only on this Mac. All buckets use the same storage service.")
        }
    }

    /// The endpoint, bucket, and region to paste; the addressing style to read.
    static func values(_ model: StorageModel, bucket: StorageBucket?) -> [ConnectionValue] {
        var values: [ConnectionValue] = [.pasteable("Endpoint", model.settings.endpoint, copy: model.copyEndpoint)]
        if let bucket {
            values.append(.pasteable("Bucket", bucket.name) { model.copyValue(bucket.name, label: "Bucket") })
        }
        values.append(
            .pasteable("Region", StorageSettings.region) { model.copyValue(StorageSettings.region, label: "Region") })
        values.append(.description("Addressing", "Path style"))
        return values
    }
}
