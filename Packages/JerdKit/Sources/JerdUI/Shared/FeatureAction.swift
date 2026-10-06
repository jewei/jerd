/// One action of a feature, shown on its dashboard card and in the menu bar menu. Each surface
/// decides how to show it.
public struct FeatureAction: Identifiable {
    /// A stable name for tests and UI tests, for example `sites.start-all`.
    public let id: String
    public let title: String
    /// The name that VoiceOver speaks. It names the subject also when the visible title is a
    /// short verb on a card, for example "Stop" speaks "Stop Storage".
    public let spokenTitle: String
    public let isEnabled: Bool
    /// True for the one next step of a card. A card shows it as the prominent button.
    public let isPrimary: Bool
    /// Why the action is off, for its tooltip and VoiceOver hint, for example "Jerd is
    /// preparing Mailpit." Nil when the action is on, or when the card already says why.
    public let unavailableReason: String?
    public let perform: @MainActor () -> Void

    public init(
        id: String, title: String, spokenTitle: String? = nil, isEnabled: Bool = true, isPrimary: Bool = false,
        unavailableReason: String? = nil, perform: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.spokenTitle = spokenTitle ?? title
        self.isEnabled = isEnabled
        self.isPrimary = isPrimary
        self.unavailableReason = isEnabled ? nil : unavailableReason
        self.perform = perform
    }

    /// The same action, off. The shell uses it for every feature action during a quit.
    public func disabled() -> FeatureAction {
        FeatureAction(
            id: id, title: title, spokenTitle: spokenTitle, isEnabled: false, isPrimary: isPrimary,
            unavailableReason: unavailableReason, perform: perform)
    }

    /// The same action with a short visible title; VoiceOver keeps the full title.
    func titled(_ shortTitle: String) -> FeatureAction {
        FeatureAction(
            id: id, title: shortTitle, spokenTitle: spokenTitle, isEnabled: isEnabled, isPrimary: isPrimary,
            unavailableReason: unavailableReason, perform: perform)
    }

    /// The same action as the next step of a card, or not.
    func marked(primary: Bool) -> FeatureAction {
        FeatureAction(
            id: id, title: title, spokenTitle: spokenTitle, isEnabled: isEnabled, isPrimary: primary,
            unavailableReason: unavailableReason, perform: perform)
    }
}
