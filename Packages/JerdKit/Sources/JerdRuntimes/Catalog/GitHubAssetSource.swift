import Foundation
import JerdFoundation
import JerdManifest

/// A runtime that a GitHub repository publishes as one release asset per architecture.
///
/// A candidate needs a stable tag with an expected prefix, the exact asset name, a GitHub
/// `sha256:` digest, and the exact download URL
/// `https://github.com/<repository>/releases/download/<tag>/<asset>` (one rule for every
/// GitHub runtime; fixes P-C2). Other assets are dropped, never fatal (P-C1).
package struct GitHubAssetSource: ReleaseSource {
    package let kind: RuntimeKind
    package let repository: String
    /// The tag forms of a release, for example `php-8.5.11` or `v2.11.4` (P-C4).
    package let tagPrefixes: [String]
    package let assetName: @Sendable (_ version: String, _ architecture: CPUArchitecture) -> String

    package func candidates(from metadata: MetadataCache, platform: HostPlatform) async throws -> [RuntimeRelease] {
        try parse(
            await metadata.data(GitHubRelease.listURL(repository: repository)), architecture: platform.architecture)
    }

    /// Pure: every recognized candidate in publisher order.
    package func parse(_ data: Data, architecture: CPUArchitecture) throws -> [RuntimeRelease] {
        try GitHubRelease.stableReleases(data).compactMap { release in
            try candidate(release, architecture: architecture)
        }
    }

    private func candidate(_ release: GitHubRelease, architecture: CPUArchitecture) throws -> RuntimeRelease? {
        guard let version = release.version(afterOneOf: tagPrefixes) else { return nil }
        let name = assetName(version, architecture)
        let expectedURL = "https://github.com/\(repository)/releases/download/\(release.tag)/\(name)"
        guard let asset = release.assets.first(where: { $0.name == name }), asset.downloadURL == expectedURL,
            asset.size > 0, let sha256 = Self.sha256(asset.digest)
        else { return nil }
        return RuntimeRelease(
            kind: kind, version: version, artifact: .archive(try .runtime(expectedURL), size: .exact(asset.size)),
            archiveSHA256: sha256,
            releasePage: try .runtime("https://github.com/\(repository)/releases/tag/\(release.tag)"),
            architecture: architecture)
    }

    /// The hexadecimal part of a GitHub `sha256:<hex>` digest, when it is valid.
    package static func sha256(_ digest: String?) -> String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = String(digest.dropFirst(7))
        return FileDigest.isSHA256Hex(hex) ? hex : nil
    }
}

extension GitHubAssetSource {
    package static let php = GitHubAssetSource(kind: .php, repository: "lerd-env/php", tagPrefixes: ["php-"]) {
        "lerd-php-\($0)-darwin-\($1.rawValue).tar.gz"
    }
    package static let caddy = GitHubAssetSource(kind: .caddy, repository: "caddyserver/caddy", tagPrefixes: ["v"]) {
        "caddy_\($0)_mac_\($1.goName).tar.gz"
    }
    package static let mailpit = GitHubAssetSource(kind: .mailpit, repository: "axllent/mailpit", tagPrefixes: ["v"]) {
        "mailpit-darwin-\($1.goName).tar.gz"
    }
    package static let rustfs = GitHubAssetSource(kind: .rustfs, repository: "rustfs/rustfs", tagPrefixes: ["", "v"]) {
        "rustfs-macos-\($1.rustName)-v\($0).zip"
    }
    /// Postgres.app with PostgreSQL 18 only. The version is the Postgres.app version.
    package static let postgresql = GitHubAssetSource(
        kind: .postgresql, repository: "PostgresApp/PostgresApp", tagPrefixes: ["v"]
    ) { version, _ in "Postgres-\(version)-18.dmg" }
    package static let cloudflared = GitHubAssetSource(
        kind: .cloudflared, repository: "cloudflare/cloudflared", tagPrefixes: [""]
    ) { "cloudflared-darwin-\($1.goName).tgz" }
}
