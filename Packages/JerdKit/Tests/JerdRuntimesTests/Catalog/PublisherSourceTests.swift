import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

@Suite struct PublisherSourceTests {
    private let platform = HostPlatform(architecture: .arm64, osMajor: 15)

    @Test func composerUsesTheFirstStableVersionAndItsPublishedChecksum() throws {
        let (version, url) = try ComposerReleaseSource.parseVersions(Fixture.data("Catalog/composer-versions.json"))
        #expect(version == "2.10.3")
        #expect(url.absoluteString == "https://getcomposer.org/download/2.10.3/composer.phar")
        let release = try ComposerReleaseSource.release(
            version: version, url: url, checksum: Fixture.text("Catalog/composer.phar.sha256sum"), architecture: .arm64)
        #expect(release.archiveSHA256 == "7a2d379d5b8ffdaa028580ef26494c36d2feef4b178d3dd1473a4dbc5e17c8d6")
        #expect(release.artifact == .archive(url, size: .atMost(20_000_000)))
    }

    @Test func composerMetadataWithAnotherPathOrChecksumIsInvalid() throws {
        let other = Data(#"{"stable":[{"version":"2.10.3","path":"/download/evil/composer.phar"}]}"#.utf8)
        #expect(throws: JerdError.invalid("Composer metadata is invalid.")) {
            try ComposerReleaseSource.parseVersions(other)
        }
        let url = try URL.runtime("https://getcomposer.org/download/2.10.3/composer.phar")
        #expect(throws: JerdError.invalid("Composer metadata is invalid.")) {
            try ComposerReleaseSource.release(version: "2.10.3", url: url, checksum: "", architecture: .arm64)
        }
    }

    @Test func laravelUsesTheNewestStableTagAndComposerResolution() throws {
        let releases = try LaravelReleaseSource().parse(
            Fixture.data("Catalog/github-laravel_installer.json"), architecture: .arm64)
        #expect(releases.map(\.version) == ["5.32.0"])
        #expect(releases.first?.artifact == .composerPackage("laravel/installer"))
        #expect(releases.first?.verification == .composerLock)
    }

    @Test func redisListsStableVersionsFromEightWithTheirDigests() throws {
        let releases = try RedisReleaseSource.parse(Fixture.text("Catalog/redis-hashes-README"), architecture: .arm64)
        #expect(releases.allSatisfy { ($0.parsedVersion?.components[0] ?? 0) >= 8 })
        #expect(!releases.contains { $0.version.contains("rc") })
        let pinned = try #require(releases.first { $0.version == "8.8.3" })
        #expect(pinned.archiveSHA256 == "13dbcfc6107ab8b6ab2a4f4582678143d5b2fd03ba38611b810359564cfe8a3c")
        #expect(pinned.artifact.downloadURL?.absoluteString == "https://download.redis.io/releases/redis-8.8.3.tar.gz")
        #expect(Set(releases.map(\.version)).count == releases.count)
    }

    @Test func mysqlPageGivesSignedPackagesForThisSystem() throws {
        let releases = try MySQLReleaseSource.parse(Fixture.text("Catalog/mysql-downloads.html"), platform: platform)
        let release = try #require(releases.first)
        #expect(releases.count == 1)
        #expect(release.version == "8.4.11" && release.minimumOSMajor == 15)
        #expect(
            release.artifact.downloadURL?.absoluteString
                == "https://cdn.mysql.com/Downloads/MySQL-8.4/mysql-8.4.11-macos15-arm64.tar.gz")
        #expect(
            release.signatureURL?.absoluteString
                == "https://cdn.mysql.com/Downloads/MySQL-8.4/mysql-8.4.11-macos15-arm64.tar.gz.asc")
        #expect(release.verification == .publisherSignature)
    }

    @Test func mysqlFiltersCompatibilityBeforeDeduplicating() throws {
        let page =
            "mysql-8.4.11-macos27-arm64.tar.gz mysql-8.4.11-macos15-arm64.tar.gz mysql-8.4.11-macos15-arm64.tar.gz"
        let releases = try MySQLReleaseSource.parse(page, platform: platform)
        #expect(releases.map { $0.artifact.downloadURL?.lastPathComponent } == ["mysql-8.4.11-macos15-arm64.tar.gz"])
        #expect(try MySQLReleaseSource.parse(page, platform: HostPlatform(architecture: .arm64, osMajor: 14)).isEmpty)
    }

    @Test func mysqlPageWithoutAnyPackageIsReportedAsChanged() {
        #expect(
            throws: JerdError.unavailable(
                "The MySQL download page changed. Jerd found no MySQL 8.4 package for this Mac.")
        ) {
            try MySQLReleaseSource.parse("<html>redesigned</html>", platform: platform)
        }
    }
}
