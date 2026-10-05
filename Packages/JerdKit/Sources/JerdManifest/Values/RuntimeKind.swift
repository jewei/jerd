/// The runtimes that Jerd supplies. The raw values are saved in receipts and folder names.
///
/// The case order is the order of the Runtimes page and of a full catalog check.
public enum RuntimeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case php
    case caddy
    case composer
    case laravel
    case mysql
    case postgresql
    case redis
    case mailpit
    case rustfs
    case cloudflared

    public var id: String { rawValue }

    /// The name that the user sees.
    public var title: String {
        switch self {
        case .php: "PHP"
        case .caddy: "Caddy"
        case .composer: "Composer"
        case .laravel: "Laravel installer"
        case .mysql: "MySQL"
        case .postgresql: "PostgreSQL"
        case .redis: "Redis"
        case .mailpit: "Mailpit"
        case .rustfs: "RustFS"
        case .cloudflared: "Cloudflare Tunnel"
        }
    }

    /// True for the kinds that are PHP scripts run by a PHP runtime, not native executables.
    public var isPHPScript: Bool { self == .composer || self == .laravel }
}
