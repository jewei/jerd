/// The footer buttons of a `SheetScaffold`. The default button is always the button on the far
/// right: the confirm button of a Cancel and confirm footer, or the one button of a Done footer.
public struct SheetConfirmation {
    public let title: String
    /// The cancel button left of the confirm button, or nil for a footer with only the confirm
    /// button (`done(_:secondary:identifier:perform:)`).
    public let cancelTitle: String?
    public let isDestructive: Bool
    public let isEnabled: Bool
    /// The button on the leading side for work inside the sheet, or nil.
    public let secondary: SheetSecondaryAction?
    /// The stable name of the sheet for UI tests, for example `site-editor`. The buttons get
    /// `site-editor.confirm`, `site-editor.cancel`, and `site-editor.secondary`.
    public let identifier: String?
    /// The button that Return presses. A destructive confirm never gets it.
    public let returnKey: SheetReturnKey
    public let perform: @MainActor () -> Void

    /// A footer with Cancel and a confirm button.
    /// - Parameter returnKey: The button that Return presses. By default the confirm button,
    ///   or no button for a destructive confirm. `.confirm` with a destructive confirm reads as
    ///   `.none`.
    public init(
        _ title: String, cancelTitle: String = "Cancel", isDestructive: Bool = false, isEnabled: Bool = true,
        returnKey: SheetReturnKey? = nil, secondary: SheetSecondaryAction? = nil, identifier: String? = nil,
        perform: @escaping @MainActor () -> Void
    ) {
        self.init(
            title, cancelTitle: Optional(cancelTitle), isDestructive: isDestructive, isEnabled: isEnabled,
            returnKey: returnKey, secondary: secondary, identifier: identifier, perform: perform)
    }

    private init(
        _ title: String, cancelTitle: String?, isDestructive: Bool, isEnabled: Bool, returnKey: SheetReturnKey?,
        secondary: SheetSecondaryAction?, identifier: String?, perform: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.cancelTitle = cancelTitle
        self.isDestructive = isDestructive
        let requested = returnKey ?? (isDestructive ? .none : .confirm)
        self.returnKey = isDestructive && requested == .confirm ? .none : requested
        self.isEnabled = isEnabled
        self.secondary = secondary
        self.identifier = identifier
        self.perform = perform
    }

    /// A footer with one button that ends a sheet that only informs, for example Done. Return
    /// and Escape both end it. The button stays enabled while the sheet works.
    /// - Parameter perform: Ends the sheet, like the sheet's `cancel`.
    public static func done(
        _ title: String = "Done", secondary: SheetSecondaryAction? = nil, identifier: String? = nil,
        perform: @escaping @MainActor () -> Void
    ) -> SheetConfirmation {
        SheetConfirmation(
            title, cancelTitle: nil, isDestructive: false, isEnabled: true, returnKey: .confirm, secondary: secondary,
            identifier: identifier, perform: perform)
    }

    /// True for a Done footer: its one button ends the sheet and never starts work.
    public var endsSheet: Bool { cancelTitle == nil }

    /// Return triggers the confirm button only when the action cannot destroy data.
    public var usesReturnKey: Bool { returnKey == .confirm }

    /// The identifier of the confirm button, when the sheet has one.
    public var confirmIdentifier: String? {
        identifier.map { "\($0).confirm" }
    }

    /// The identifier of the cancel button, when the sheet has one.
    public var cancelIdentifier: String? {
        identifier.map { "\($0).cancel" }
    }

    /// The identifier of the secondary button, when the sheet has one.
    public var secondaryIdentifier: String? {
        identifier.map { "\($0).secondary" }
    }
}
