/// The confirm and cancel buttons of a `SheetScaffold`.
public struct SheetConfirmation {
    public let title: String
    public let cancelTitle: String
    public let isDestructive: Bool
    public let isEnabled: Bool
    /// The stable name of the sheet for UI tests, for example `site-editor`. The buttons get
    /// `site-editor.confirm` and `site-editor.cancel`.
    public let identifier: String?
    /// The button that Return presses. A destructive confirm never gets it.
    public let returnKey: SheetReturnKey
    public let perform: @MainActor () -> Void

    /// - Parameter returnKey: The button that Return presses. By default the confirm button,
    ///   or no button for a destructive confirm. `.confirm` with a destructive confirm reads as
    ///   `.none`.
    public init(
        _ title: String, cancelTitle: String = "Cancel", isDestructive: Bool = false, isEnabled: Bool = true,
        returnKey: SheetReturnKey? = nil, identifier: String? = nil, perform: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.cancelTitle = cancelTitle
        self.isDestructive = isDestructive
        let requested = returnKey ?? (isDestructive ? .none : .confirm)
        self.returnKey = isDestructive && requested == .confirm ? .none : requested
        self.isEnabled = isEnabled
        self.identifier = identifier
        self.perform = perform
    }

    /// Return triggers the confirm button only when the action cannot destroy data.
    public var usesReturnKey: Bool { returnKey == .confirm }

    /// Return triggers the cancel-side button, for example Done.
    public var cancelUsesReturnKey: Bool { returnKey == .cancel }

    /// The identifier of the confirm button, when the sheet has one.
    public var confirmIdentifier: String? {
        identifier.map { "\($0).confirm" }
    }

    /// The identifier of the cancel button, when the sheet has one.
    public var cancelIdentifier: String? {
        identifier.map { "\($0).cancel" }
    }
}
