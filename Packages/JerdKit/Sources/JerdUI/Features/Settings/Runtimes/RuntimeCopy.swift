import Foundation
import JerdManifest
import JerdRuntimes

/// The words and symbols of the Runtimes page, as pure functions so tests can pin them.
enum RuntimeCopy {
    /// The Runtimes check. It differs from the app's "Check for Updates…" (Sparkle), so the two
    /// visible titles never look like the same command.
    static let checkTitle = "Check for Runtime Updates"

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
        case .mysql, .postgresql, .redis: hasInstalledVersion ? "Install Version" : "Install"
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

    /// The progress text before the installer reports its first step.
    static func startingMessage(_ kind: RuntimeKind) -> String {
        "Preparing to install \(kind.title)…"
    }

    /// The section footer: when the kind was checked, then its note, or nil when there is
    /// neither. Before the first check the page says it once, not under every section.
    static func footer(_ kind: RuntimeKind, checkedAt: String?) -> String? {
        let parts = [checkedAt.map { "Checked \($0)." }, note(kind)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The one page line before the first check.
    static let notCheckedMessage = "Updates have not been checked. Select \(checkTitle) to see new versions."

    /// The detail of the pinned release that the app installs on demand, for example
    /// `8.4.11, 168 MB download. Jerd checks it against its reviewed checksum.`
    static func onDemandDetail(_ release: RuntimeRelease) -> String {
        let size = release.downloadSize.map { ", \(ByteText.format($0)) download" }
        let checks = RuntimeInstallCopy.checks(isSigned: release.pinnedSignature != nil)
        return "\(release.versionLabel)\(size ?? ""). Jerd checks it against \(checks)."
    }

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

    /// The release label in the picker. The Installed label next to the picker marks an
    /// installed release, so the picker does not say it again.
    static func releaseLabel(_ release: RuntimeRelease) -> String {
        release.versionLabel
    }
}
