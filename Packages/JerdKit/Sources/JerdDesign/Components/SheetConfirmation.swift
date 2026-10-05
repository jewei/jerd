/// The confirm and cancel buttons of a `SheetScaffold`.
public struct SheetConfirmation {
    public let title: String
    public let cancelTitle: String
    public let isDestructive: Bool
    public let isEnabled: Bool
    public let perform: @MainActor () -> Void

    public init(
        _ title: String, cancelTitle: String = "Cancel", isDestructive: Bool = false, isEnabled: Bool = true,
        perform: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.cancelTitle = cancelTitle
        self.isDestructive = isDestructive
        self.isEnabled = isEnabled
        self.perform = perform
    }

    /// Return triggers the confirm button only when the action cannot destroy data.
    public var usesReturnKey: Bool { !isDestructive }
}
