/// The rule for a sheet save that ends after the user cancelled its sheet. The sheet is gone,
/// so a success changes nothing more (no selection, no start), and a failure shows once, as the
/// page banner (spec F 3.6). A save that stopped because of the cancel is not a failure.
enum CancelledSave {
    /// The page operation after the save, or nil when the page keeps its state.
    static func pageOperation(failure error: (any Error)?) -> OperationState? {
        guard let error, !(error is CancellationError) else { return nil }
        return .failed(message: ErrorText.message(for: error))
    }
}
