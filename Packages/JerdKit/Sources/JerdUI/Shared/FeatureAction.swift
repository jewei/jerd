/// One action that a feature offers outside its own page: on its dashboard card or in the menu
/// bar. The feature decides the title and whether the action is the next step.
public struct FeatureAction: Identifiable {
    /// A stable name for tests and UI tests, for example `sites.start-all`.
    public let id: String
    public let title: String
    public let isEnabled: Bool
    /// True for the one next step of a card. A card shows it as the prominent button.
    public let isPrimary: Bool
    public let perform: @MainActor () -> Void

    public init(
        id: String, title: String, isEnabled: Bool = true, isPrimary: Bool = false,
        perform: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.isEnabled = isEnabled
        self.isPrimary = isPrimary
        self.perform = perform
    }

    /// The same action, off. The shell uses it for every feature action during a quit.
    public func disabled() -> FeatureAction {
        FeatureAction(id: id, title: title, isEnabled: false, isPrimary: isPrimary, perform: perform)
    }
}
