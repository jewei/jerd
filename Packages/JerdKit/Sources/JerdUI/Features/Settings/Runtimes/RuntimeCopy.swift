import JerdManifest
import JerdRuntimes

/// The words and symbols of the Runtimes page, as pure functions so tests can pin them.
enum RuntimeCopy {
    static func systemImage(_ kind: RuntimeKind) -> String {
        switch kind {
        case .php: "chevron.left.forwardslash.chevron.right"
        case .caddy: "globe"
        case .composer, .laravel: "shippingbox"
        case .mysql, .postgresql, .redis: "cylinder.split.1x2"
        case .mailpit: "envelope"
        case .rustfs: "externaldrive.badge.icloud"
        case .cloudflared: "network"
        }
    }

    /// The fixed note under a section, after the check date.
    static func note(_ kind: RuntimeKind) -> String? {
        switch kind {
        case .mysql: "MySQL uses the 8.4 LTS series."
        case .postgresql: "PostgreSQL uses the 18 series from Postgres.app."
        case .redis: "Redis builds need the Xcode command line tools."
        case .mailpit, .rustfs: "An update restarts this service. Jerd keeps a local data backup for recovery."
        case .cloudflared:
            "Cloudflare Tunnel uses the official cloudflared runtime. Stop Jerd tunnels before changing this runtime."
        case .php, .caddy, .composer, .laravel: nil
        }
    }

    /// The install button of a release that is not installed. PHP has its own button and menu.
    static func installTitle(_ kind: RuntimeKind, hasInstalledVersion: Bool) -> String {
        switch kind {
        case .php: "Install and Use"
        case .mysql, .postgresql, .redis: "Install Version"
        default: hasInstalledVersion ? "Update" : "Install"
        }
    }

    /// The message after an installation that finished and is in use.
    static func installedMessage(_ kind: RuntimeKind, version: String, useAsDefault: Bool) -> String {
        switch kind {
        case .mysql, .postgresql, .redis:
            "Installed \(version). Select it when adding a database service. Existing services keep their selected version."
        case .php where useAsDefault:
            "PHP \(version) is the default. Pinned sites keep their selected version."
        case .php:
            "PHP \(version) is available in each site’s PHP selection."
        default:
            "Updated to \(version)."
        }
    }

    static let cancelledMessage = "Installation cancelled."

    /// How the release is verified, for the Release row.
    static func verificationDetail(_ release: RuntimeRelease) -> String {
        switch release.verification {
        case .digest(let digest):
            "Package build \(digest.prefix(12))"
        case .publisherSignature:
            "Install checks the publisher signature of this package. Its digest is known only after download."
        case .composerLock:
            "Composer verifies this installer with its lock file. Jerd has no independent check."
        }
    }

    /// The release label in the picker, with a mark for the installed release.
    static func releaseLabel(_ release: RuntimeRelease, isInstalled: Bool) -> String {
        release.versionLabel + (isInstalled ? " · Installed" : "")
    }
}
