import JerdUI

extension ServiceScenario {
    /// Runs the steps of a storage scenario after the launch. Returns false for the other scenarios.
    @MainActor
    func prepareStorageScenario(_ state: AppState) async -> Bool {
        let model = state.storage
        switch self {
        case .addBucket:
            model.beginAddBucket()
            model.bucketDraft?.name = "studio-uploads"
        case .addBucketInvalid:
            model.beginAddBucket()
            model.bucketDraft = BucketDraft(name: "Studio_Uploads", publicRead: true)
        case .storagePorts:
            // Ports can change only while storage is stopped, as in the app.
            await model.stop()?.value
            model.editPorts()
        default:
            return false
        }
        return true
    }
}
