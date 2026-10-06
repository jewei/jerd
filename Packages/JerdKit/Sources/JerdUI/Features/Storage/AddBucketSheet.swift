import JerdDesign
import JerdStorage
import SwiftUI

/// The Add Bucket sheet: a name with its rules inline, and the public-read choice explained as
/// read-only access. Package access lets the snapshot catalog render it alone.
package struct AddBucketSheet: View {
    @Bindable var model: StorageModel
    @FocusState private var isNameFocused: Bool
    @Environment(\.isQuitting) private var isQuitting

    package init(model: StorageModel) {
        self.model = model
    }

    package var body: some View {
        SheetScaffold(
            "Add Bucket", message: "Jerd starts storage if needed, then creates and checks your bucket.",
            confirmation: SheetConfirmation(
                "Create Bucket", isEnabled: draft.canSave(in: model.settings) && !isQuitting, identifier: "add-bucket"
            ) { model.saveBucket() },
            workingMessage: model.bucketOperation.workingMessage, cancel: model.cancelAddBucket
        ) {
            Section {
                TextField("Bucket name", text: binding.name, prompt: Text("my-app-uploads"))
                    .focused($isNameFocused)
                    .accessibilityIdentifier("add-bucket.name")
                if let issue = draft.issue(in: model.settings) {
                    InlineMessage(issue, kind: .warning, identifier: "add-bucket.issue")
                }
                Toggle("Allow public read access", isOn: binding.publicRead)
                    .accessibilityIdentifier("add-bucket.public-read")
            } footer: {
                FormFooter(accessText)
            }
            Section {
                ValueRow("Endpoint", value: model.settings.endpoint, isCode: true)
                ValueRow("Region", value: StorageSettings.region, isCode: true)
            }
            if let failure = model.bucketOperation.failureMessage {
                Section {
                    InlineMessage(failure, kind: .error, identifier: "add-bucket.error")
                }
            }
        }
        .onAppear { isNameFocused = true }
    }

    private var draft: BucketDraft { model.bucketDraft ?? BucketDraft() }

    private var accessText: String {
        draft.publicRead
            ? "Anyone on this Mac who knows an object URL can read it. Nobody can upload, delete, or list objects without credentials."
            : "The bucket is private. Reading and writing objects requires credentials. Use 3–63 lowercase letters, numbers, dots, or hyphens."
    }

    private var binding: Binding<BucketDraft> {
        Binding {
            model.bucketDraft ?? BucketDraft()
        } set: { draft in
            model.bucketDraft = draft
        }
    }
}
