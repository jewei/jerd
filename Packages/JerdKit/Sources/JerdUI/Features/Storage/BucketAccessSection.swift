import JerdDesign
import JerdStorage
import SwiftUI

/// The access of one bucket, the shared keys, and its Laravel settings.
struct BucketAccessSection: View {
    let model: StorageModel
    let bucket: StorageBucket

    var body: some View {
        Section {
            LabeledContent("Bucket access") {
                Label(bucket.publicRead ? "Public read" : "Private", systemImage: bucket.publicRead ? "eye" : "lock")
            }
            StorageCredentialsSection.rows(model: model)
        } header: {
            Text("Access")
        } footer: {
            FormFooter(
                bucket.publicRead
                    ? "Anyone on this Mac who knows an object URL can read it. Uploads, deletes, and listings require credentials."
                    : "Credentials are required to read and write objects.")
        }
        Section {
            ActionRow(".env settings", detail: laravelDetail) {
                CopyLaravelSettingsButton(isEnabled: canCopyEnvironment, identifier: "bucket.copy-laravel") {
                    model.copyEnvironment(for: bucket)
                }
            }
        } header: {
            Text("Laravel")
        } footer: {
            FormFooter(
                "Laravel needs its S3 filesystem adapter. Paste the settings into your application's .env file, then clear any cached configuration."
            )
        }
    }

    private var canCopyEnvironment: Bool { bucket.setupComplete && model.hasCredentials }

    private var laravelDetail: String? {
        if !bucket.setupComplete { return "Available after the bucket setup finishes." }
        return model.hasCredentials ? nil : "Start storage once to create its credentials."
    }
}
