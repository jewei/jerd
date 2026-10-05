/// The kinds of services that save active-run records, in the order that recovery lists them.
public enum RecordFamily: String, CaseIterable, Sendable, Comparable {
    case mail
    case storage
    case database
    case tunnel
    case web

    /// The name shown to a user and used as the first part of a record ID.
    public var displayName: String {
        switch self {
        case .mail: "Mail"
        case .storage: "Storage"
        case .database: "Database"
        case .tunnel: "Tunnel"
        case .web: "Web"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)
    }
}
