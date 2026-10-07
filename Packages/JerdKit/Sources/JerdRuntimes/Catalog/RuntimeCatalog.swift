import Foundation
import JerdFoundation
import JerdManifest

/// Checks the publisher catalogs. It reads the network only when a check is requested.
///
/// Each candidate passes the release policy alone: an invalid or incompatible candidate is
/// dropped and the others stay. The result is sorted newest first.
public actor RuntimeCatalog {
    private let metadata: MetadataCache
    private let policy: ReleasePolicy
    private let now: @Sendable () -> Date

    public init(
        fetcher: any HTTPFetching, policy: ReleasePolicy = ReleasePolicy(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        metadata = MetadataCache(fetcher: fetcher, now: now)
        self.policy = policy
        self.now = now
    }

    /// Checks one kind. Never throws: a failure is in `error`.
    public func check(_ kind: RuntimeKind) async -> RuntimeUpdateCheck {
        do {
            let releases = try await installableReleases(kind)
            return RuntimeUpdateCheck(kind: kind, releases: releases, checkedAt: now(), error: nil)
        } catch is CancellationError {
            return RuntimeUpdateCheck(kind: kind, releases: [], checkedAt: now(), error: "The check was cancelled.")
        } catch {
            return RuntimeUpdateCheck(
                kind: kind, releases: [], checkedAt: now(), error: FailureDetail.describe(error))
        }
    }

    private func installableReleases(_ kind: RuntimeKind) async throws -> [RuntimeRelease] {
        let candidates = try await Self.source(for: kind).candidates(from: metadata, platform: policy.platform)
        let accepted = candidates.filter { policy.check($0) == nil }
        guard !accepted.isEmpty else {
            throw JerdError.unavailable("No supported stable macOS package is available from this source.")
        }
        // The policy accepts only parseable versions, so no candidate is lost here.
        let versioned = accepted.compactMap { release in release.parsedVersion.map { (release, $0) } }
        return versioned.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// The one source of each kind.
    static func source(for kind: RuntimeKind) -> any ReleaseSource {
        switch kind {
        case .php: GitHubAssetSource.php
        case .caddy: GitHubAssetSource.caddy
        case .composer: ComposerReleaseSource()
        case .laravel: LaravelReleaseSource()
        case .mysql: MySQLReleaseSource()
        case .postgresql: GitHubAssetSource.postgresql
        case .redis: RedisReleaseSource()
        case .mailpit: GitHubAssetSource.mailpit
        case .rustfs: GitHubAssetSource.rustfs
        case .cloudflared: GitHubAssetSource.cloudflared
        }
    }
}
