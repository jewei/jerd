import Foundation
import JerdManifest
import JerdRuntimes
import JerdUI

/// Realistic, deterministic sample values. Dates are fixed; nothing depends on the Mac.
public enum SampleData {
    /// 6 October 2026, 09:41 GMT.
    public static let now = Date(timeIntervalSince1970: 1_791_279_660)
    public static let digest = "3f7c2a9b41d8e6f0a5c4b3d2e1f09876543210fedcba9876543210fedcba98"
    public static let php84ID = UUID(uuidString: "8A4C2E10-1D3F-4B5A-9C6E-7F8091A2B3C4") ?? UUID()
    public static let php83ID = UUID(uuidString: "3B5D7F90-2E4A-4C6B-8D0F-1A2B3C4D5E6F") ?? UUID()

    /// A URL from a literal that is known to be valid.
    public static func url(_ text: String) -> URL {
        URL(string: text) ?? URL(fileURLWithPath: "/")
    }

    public static let user = "/Users/developer"

    /// The installed runtimes of a set-up Mac.
    public static let inventory = RuntimeInventorySnapshot(
        versions: [
            .php: ["8.4.12", "8.3.24"], .caddy: ["2.10.2"], .composer: ["2.8.11"], .laravel: ["5.18.0"],
            .mysql: ["8.4.6"], .postgresql: ["17.6"], .redis: ["8.2.1"], .mailpit: ["1.27.7"], .rustfs: ["1.0.0"],
            .cloudflared: ["2025.9.1"],
        ],
        phpBuildDigests: [php84ID: digest],
        builds: [InstalledBuild(kind: .caddy, version: "2.10.2", releaseVersion: "2.10.2", archiveSHA256: digest)])

    /// A Mac with an app that installs the database engines on demand: none is installed yet.
    public static let onDemandInventory: RuntimeInventorySnapshot = {
        var snapshot = inventory
        for kind in [RuntimeKind.mysql, .postgresql] { snapshot.versions[kind] = [] }
        snapshot.onDemand = onDemandReleases
        return snapshot
    }()

    /// The pinned database releases of the committed catalog.
    public static let onDemandReleases = [
        pinned(
            .mysql, "8.4.11", "https://cdn.mysql.com/Downloads/MySQL-8.4/mysql-8.4.11-macos15-arm64.tar.gz",
            167_977_240,
            installed: 321_049_835,
            signature: PinnedFile(
                url: url("https://cdn.mysql.com/Downloads/MySQL-8.4/mysql-8.4.11-macos15-arm64.tar.gz.asc"),
                sizeLimit: 16_384, sha256: digest)),
        pinned(
            .postgresql, "2.9.6",
            "https://github.com/PostgresApp/PostgresApp/releases/download/v2.9.6/Postgres-2.9.6-18.dmg",
            122_517_005, installed: 750_547_900, engineVersion: "18.6"),
    ]

    private static func pinned(
        _ kind: RuntimeKind, _ version: String, _ link: String, _ size: Int64, installed: Int64,
        engineVersion: String? = nil, signature: PinnedFile? = nil
    ) -> RuntimeRelease {
        RuntimeRelease(
            kind: kind, version: version, artifact: .archive(url(link), size: .exact(size)), archiveSHA256: digest,
            signatureURL: signature?.url, releasePage: url("https://github.com/jewei/jerd"),
            pinnedSignature: signature, engineVersion: engineVersion, installedSize: installed)
    }

    /// A release with a stated digest.
    public static func release(
        _ kind: RuntimeKind, _ version: String, digest: String? = SampleData.digest, signed: Bool = false
    ) -> RuntimeRelease {
        RuntimeRelease(
            kind: kind, version: version,
            artifact: .archive(url("https://example.com/\(kind.rawValue)-\(version).tar.gz"), size: .exact(48_000_000)),
            archiveSHA256: digest,
            signatureURL: signed ? url("https://example.com/\(kind.rawValue)-\(version).asc") : nil,
            releasePage: url("https://example.com/\(kind.rawValue)/releases/\(version)"))
    }

    /// A check result, checked at `now`.
    public static func check(
        _ kind: RuntimeKind, _ releases: [RuntimeRelease], error: String? = nil
    )
        -> RuntimeUpdateCheck
    {
        RuntimeUpdateCheck(kind: kind, releases: releases, checkedAt: now, error: error)
    }

    /// Check results for every kind: new releases, an installed release, and a failed source.
    public static let checks: [RuntimeKind: RuntimeUpdateCheck] = [
        .php: check(.php, [release(.php, "8.5.0"), release(.php, "8.4.13"), release(.php, "8.3.26")]),
        .caddy: check(.caddy, [release(.caddy, "2.10.2")]),
        .composer: check(.composer, [release(.composer, "2.8.12")]),
        .laravel: check(.laravel, [release(.laravel, "5.19.0", digest: nil)]),
        .mysql: check(.mysql, [release(.mysql, "8.4.7", digest: nil, signed: true)]),
        .postgresql: check(.postgresql, [release(.postgresql, "2.9.1")]),
        .redis: check(.redis, [], error: "The Redis release list could not be read. Try again later."),
        .mailpit: check(.mailpit, [release(.mailpit, "1.28.0")]),
        .rustfs: check(.rustfs, [release(.rustfs, "1.0.1")]),
        .cloudflared: check(.cloudflared, [release(.cloudflared, "2025.10.0")]),
    ]
}
