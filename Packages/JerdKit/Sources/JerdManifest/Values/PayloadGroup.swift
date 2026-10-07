/// The first-launch installation groups of bundled payloads. Each group installs into its own folder.
public enum PayloadGroup: String, Codable, CaseIterable, Sendable {
    /// PHP, Caddy, Composer, and the Laravel installer.
    case development
    /// MySQL, PostgreSQL, and Redis.
    case database
    /// Mailpit.
    case mail
    /// RustFS.
    case storage

    /// The group of a runtime kind, or nil for a kind that is never bundled.
    public init?(kind: RuntimeKind) {
        switch kind {
        case .php, .caddy, .composer, .laravel: self = .development
        case .mysql, .postgresql, .redis: self = .database
        case .mailpit: self = .mail
        case .rustfs: self = .storage
        case .cloudflared: return nil
        }
    }

    /// The kinds of this group, in catalog order.
    public var kinds: [RuntimeKind] { RuntimeKind.allCases.filter { PayloadGroup(kind: $0) == self } }
}
