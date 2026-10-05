import Foundation
import JerdManifest
import JerdRuntimes
import Testing

@Suite struct GitHubAssetSourceTests {
    @Test func phpReleasesUseTheExactLerdAssetForEachArchitecture() throws {
        let data = try Fixture.data("Catalog/github-lerd-env_php.json")
        let arm = try GitHubAssetSource.php.parse(data, architecture: .arm64)
        #expect(arm.map(\.version).prefix(3) == ["8.5.11", "8.4.26", "8.3.35"])
        let newest = try #require(arm.first)
        #expect(newest.archiveSHA256 == "59761adfe93cf737282843ea1cbc74e2fef3dd86839554efd71c3dddb2b867dc")
        let url = try URL.runtime(
            "https://github.com/lerd-env/php/releases/download/php-8.5.11/lerd-php-8.5.11-darwin-arm64.tar.gz")
        #expect(newest.artifact == .archive(url, size: .exact(66_723_803)))
        #expect(newest.releasePage.absoluteString == "https://github.com/lerd-env/php/releases/tag/php-8.5.11")
        let intel = try GitHubAssetSource.php.parse(data, architecture: .intel)
        #expect(intel.first?.artifact.downloadURL?.lastPathComponent == "lerd-php-8.5.11-darwin-x86_64.tar.gz")
        #expect(intel.allSatisfy { $0.architecture == .intel })
    }

    @Test func caddyPrereleasesAreDropped() throws {
        let releases = try GitHubAssetSource.caddy.parse(
            Fixture.data("Catalog/github-caddyserver_caddy.json"), architecture: .arm64)
        #expect(releases.map(\.version) == ["2.11.7", "2.11.6", "2.11.4", "2.11.3", "2.11.2", "2.11.1"])
        #expect(releases.first?.artifact.downloadURL?.lastPathComponent == "caddy_2.11.7_mac_arm64.tar.gz")
    }

    @Test func mailpitAndRustFSUseTheirPublisherArchitectureNames() throws {
        let mailpit = try GitHubAssetSource.mailpit.parse(
            Fixture.data("Catalog/github-axllent_mailpit.json"), architecture: .intel)
        #expect(mailpit.first?.artifact.downloadURL?.lastPathComponent == "mailpit-darwin-amd64.tar.gz")
        let rustfs = try GitHubAssetSource.rustfs.parse(
            Fixture.data("Catalog/github-rustfs_rustfs.json"), architecture: .arm64)
        #expect(rustfs.map(\.version) == ["1.0.1", "1.0.0"])
        #expect(rustfs.last?.archiveSHA256 == "06e32a681c16930fb5414df64c96151fe3370321fab0403a83a83a015874c39a")
    }

    @Test func postgresAppOffersOnlyTheStablePostgreSQL18Image() throws {
        let releases = try GitHubAssetSource.postgresql.parse(
            Fixture.data("Catalog/github-PostgresApp_PostgresApp.json"), architecture: .arm64)
        #expect(releases.map(\.version) == ["2.9.6"])
        #expect(releases.first?.artifact.downloadURL?.lastPathComponent == "Postgres-2.9.6-18.dmg")
        #expect(releases.first?.archiveSHA256 == "9fc7d0dc08cf46dfd94bb32cbaaad81b41b37847a42d6dcb2f9fbd292813defb")
    }

    @Test func cloudflaredReleasesFromTheRealListParse() throws {
        let releases = try GitHubAssetSource.cloudflared.parse(
            Fixture.data("Catalog/github-cloudflare_cloudflared.json"), architecture: .arm64)
        #expect(releases.first?.version == "2026.9.3")
        #expect(releases.first?.archiveSHA256 == "587c2cfb1c230fe36c7fa7727da78be459dae028cabe8c001291999350f07095")
    }

    @Test func candidatesWithoutAStableTagExactURLOrValidDigestAreDropped() throws {
        let data = try GitHubListBuilder.cloudflared(entries: [
            .init(), .init(tag: "2026.9.4-beta"), .init(prerelease: true), .init(draft: true),
            .init(digest: "sha256:invalid"), .init(digest: nil), .init(repository: "other/cloudflared"),
            .init(platform: "linux"), .init(tag: "v2026.9.5"),
        ])
        for architecture in CPUArchitecture.allCases {
            let releases = try GitHubAssetSource.cloudflared.parse(data, architecture: architecture)
            #expect(releases.map(\.version) == ["2026.9.3"])
            #expect(releases.first?.architecture == architecture)
            #expect(
                releases.first?.artifact.downloadURL?.lastPathComponent
                    == "cloudflared-darwin-\(architecture.goName).tgz")
        }
    }

    @Test func tagPrefixMustMatchTheRepository() throws {
        let data = try GitHubListBuilder.cloudflared(entries: [.init(tag: "php-2026.9.3")])
        #expect(try GitHubAssetSource.cloudflared.parse(data, architecture: .arm64).isEmpty)
    }

    @Test func malformedListIsInvalidMetadata() {
        #expect(throws: GitHubRelease.invalidMetadata) {
            try GitHubAssetSource.php.parse(Data("{}".utf8), architecture: .arm64)
        }
    }
}

/// Builds GitHub release lists for cloudflared with one changed property per entry.
enum GitHubListBuilder {
    struct Entry {
        var tag = "2026.9.3"
        var prerelease = false
        var draft = false
        var digest: String? = "sha256:\(String(repeating: "a", count: 64))"
        var repository = "cloudflare/cloudflared"
        var platform = "darwin"
    }

    static func cloudflared(entries: [Entry]) throws -> Data {
        let list = entries.map { entry -> [String: Any] in
            let assets = ["arm64", "amd64"].map { arch -> [String: Any] in
                let name = "cloudflared-\(entry.platform)-\(arch).tgz"
                var asset: [String: Any] = [
                    "name": name, "size": 20_000_000,
                    "browser_download_url":
                        "https://github.com/\(entry.repository)/releases/download/\(entry.tag)/\(name)",
                ]
                if let digest = entry.digest { asset["digest"] = digest }
                return asset
            }
            return ["tag_name": entry.tag, "draft": entry.draft, "prerelease": entry.prerelease, "assets": assets]
        }
        return try JSONSerialization.data(withJSONObject: list)
    }
}
