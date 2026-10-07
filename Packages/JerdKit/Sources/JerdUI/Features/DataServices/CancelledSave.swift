/// The rule for a sheet save that ends after the user cancelled its sheet. The sheet is gone,
/// so a success changes nothing more (no selection, no start), and a failure shows once, as the
/// page banner. A save that stopped because of the cancel is not a failure.
enum CancelledSave {
    /// The page operation after the save, or nil when the page keeps its state.
    static func pageOperation(failure error: (any Error)?) -> OperationState? {
        guard let error, !(error is CancellationError) else { return nil }
        return .failed(message: ErrorText.message(for: error))
    }

    /// The one line that the page shows while a cancelled save still runs, because the save
    /// keeps `controls` off until it ends.
    static func pendingMessage(_ controls: String) -> String {
        "A cancelled change is still finishing. \(controls) wait for it."
    }
}
