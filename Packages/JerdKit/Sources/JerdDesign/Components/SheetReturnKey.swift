/// The footer button of a `SheetScaffold` that Return presses. Only the button on the far right
/// can get it, so the default button is always where the HIG puts it.
public enum SheetReturnKey: Sendable {
    /// The confirm button, for example Save or Done. Never for a destructive confirm.
    case confirm
    /// No button: Return does nothing, for example when the confirm starts long work.
    case none
}
