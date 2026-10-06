import JerdDesign
import SwiftUI

/// The shared access key and secret key. They exist after the first start.
struct StorageCredentialsSection: View {
    let model: StorageModel

    var body: some View {
        Section {
            Self.rows(model: model)
        } header: {
            Text("Credentials")
        } footer: {
            FormFooter("Use the shared access key and secret key to sign requests and to sign in to the console.")
        }
    }

    /// The two key rows, also on the bucket page.
    @ViewBuilder
    static func rows(model: StorageModel) -> some View {
        ActionRow("Access key", detail: model.hasCredentials ? nil : "Start storage once to create its credentials.") {
            Button("Copy Access Key", systemImage: "key") { model.copyAccessKey() }
                .disabled(!model.hasCredentials)
                .accessibilityIdentifier("storage.copy-access-key")
        }
        ActionRow("Secret key") {
            Button("Copy Secret Key", systemImage: "key") { model.copySecretKey() }
                .disabled(!model.hasCredentials)
                .accessibilityIdentifier("storage.copy-secret-key")
        }
    }
}
