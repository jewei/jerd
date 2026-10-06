/// The next step of a tunnel page, which its header shows as the primary action.
public enum TunnelNextStep: Equatable, Sendable {
    /// The connector runs: open the public address.
    case open
    /// The connector failed, or its settings need an edit: fix the registration first.
    case edit
    /// The connector is stopped and its settings look right: connect it.
    case connect

    /// The title of the header button.
    public var title: String {
        switch self {
        case .open: "Open in Browser"
        case .edit: "Edit Tunnel…"
        case .connect: "Connect…"
        }
    }
}
