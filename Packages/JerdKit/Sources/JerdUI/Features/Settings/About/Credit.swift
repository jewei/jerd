import Foundation

/// One project that Jerd uses, with its role and home page. The order is a contract.
struct Credit: Identifiable, Equatable {
    let name: String
    let role: String
    let address: String

    var id: String { name }
    var url: URL? { URL(string: address) }

    static let all: [Credit] = [
        Credit(name: "PHP", role: "PHP CLI and PHP-FPM", address: "https://www.php.net/"),
        Credit(name: "Lerd PHP builds", role: "Native PHP packages", address: "https://github.com/lerd-env/php"),
        Credit(name: "Caddy", role: "Local web server and TLS", address: "https://caddyserver.com/"),
        Credit(
            name: "cloudflared", role: "Cloudflare Tunnel connector", address: "https://github.com/cloudflare/cloudflared"),
        Credit(name: "Composer", role: "PHP dependency manager", address: "https://getcomposer.org/"),
        Credit(name: "Laravel", role: "Application installer", address: "https://laravel.com/"),
        Credit(name: "MySQL", role: "Database server", address: "https://www.mysql.com/"),
        Credit(name: "PostgreSQL", role: "Database server", address: "https://www.postgresql.org/"),
        Credit(name: "Postgres.app", role: "Native PostgreSQL packages", address: "https://postgresapp.com/"),
        Credit(name: "Redis", role: "In-memory data store", address: "https://redis.io/"),
        Credit(name: "Mailpit", role: "Local mail capture", address: "https://mailpit.axllent.org/"),
        Credit(name: "RustFS", role: "S3-compatible object storage", address: "https://rustfs.com/"),
        Credit(name: "libarchive", role: "Runtime archive extraction", address: "https://www.libarchive.org/"),
        Credit(name: "Sparkle", role: "Signed app updates", address: "https://sparkle-project.org/"),
    ]
}
