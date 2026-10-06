/// The one button rule of every dashboard card (JerdUI README, "Dashboard cards").
///
/// A card has at most two actions, in this order: its lifecycle action, then its Open step.
/// The next step is the only primary action: the Open step while it can run, else Add or Start.
/// Stop is never primary. Lifecycle titles are short verbs ("Start", "Stop All"), because the
/// card title names the subject, so both actions fit in one row at the minimum window size on
/// every card; their spoken titles keep the subject.
enum CardActionRule {
    /// The action that changes whether the feature runs, or Add when it has nothing yet.
    enum Lifecycle {
        case add(FeatureAction)
        case start(FeatureAction)
        case stop(FeatureAction)
    }

    /// The card actions with the primary flag of the rule.
    /// - Parameter open: The Open step (Open Console, Open Inbox, Open Site). Pass it only while
    ///   the feature runs; a stopped feature has nothing to open.
    static func actions(_ lifecycle: Lifecycle?, open: FeatureAction? = nil) -> [FeatureAction] {
        let opensNext = open?.isEnabled ?? false
        var actions: [FeatureAction] = []
        switch lifecycle {
        case .add(let action), .start(let action):
            actions.append(action.marked(primary: action.isEnabled && !opensNext))
        case .stop(let action):
            actions.append(action.marked(primary: false))
        case nil:
            break
        }
        if let open { actions.append(open.marked(primary: opensNext)) }
        return actions
    }
}
