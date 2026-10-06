/// The footer button of a `SheetScaffold` that Return presses.
public enum SheetReturnKey: Sendable {
    /// The confirm button, for example Save. Never for a destructive confirm.
    case confirm
    /// The cancel-side button, for a sheet whose usual end is a plain Done or Close.
    case cancel
    /// No button: Return does nothing, for example when the confirm starts long work.
    case none
}
