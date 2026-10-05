/// The confirm and cancel buttons of a `SheetScaffold`.
public struct SheetConfirmation {
    public let title: String
    public let cancelTitle: String
    public let isDestructive: Bool
    public let isEnabled: Bool
    /// The stable name of the sheet for UI tests, for example `site-editor`. The buttons get
    /// `site-editor.confirm` and `site-editor.cancel`.
    public let identifier: String?
    public let perform: @MainActor () -> Void

    public init(
        _ title: String, cancelTitle: String = "Cancel", isDestructive: Bool = false, isEnabled: Bool = true,
        identifier: String? = nil, perform: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.cancelTitle = cancelTitle
        self.isDestructive = isDestructive
        self.isEnabled = isEnabled
        self.identifier = identifier
        self.perform = perform
    }

    /// Return triggers the confirm button only when the action cannot destroy data.
    public var usesReturnKey: Bool { !isDestructive }

    /// The identifier of the confirm button, when the sheet has one.
    public var confirmIdentifier: String? {
        identifier.map { "\($0).confirm" }
    }

    /// The identifier of the cancel button, when the sheet has one.
    public var cancelIdentifier: String? {
        identifier.map { "\($0).cancel" }
    }
}
