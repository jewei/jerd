/// The next step of a site page, which its header shows as the primary action.
public enum SiteNextStep: Equatable, Sendable {
    /// An interrupted HTTPS setup blocks every change: recover it in Advanced first.
    case recover
    /// The site runs: open it.
    case open
    /// The site is stopped. `needsApproval` adds "…", because Start then opens the approval.
    case start(needsApproval: Bool)

    /// The title of the header button.
    public var title: String {
        switch self {
        case .recover: "Open Advanced"
        case .open: "Open in Browser"
        case .start(let needsApproval): needsApproval ? "Start Site…" : "Start Site"
        }
    }
}
