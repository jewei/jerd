import Foundation
import JerdFoundation
import JerdManifest
import Testing

@Suite struct RuntimePinCatalogTests {
    private func committedCatalog() throws -> RuntimePinCatalog {
        try RuntimePinCatalog.decode(Data(contentsOf: Fixture.repositoryFile("Runtimes/runtimes.json")))
    }

    @Test func committedCatalogIsValidAndCoversEveryBundledKindOnce() throws {
        let catalog = try committedCatalog()
        #expect(catalog.architecture == .arm64)
        #expect(
            catalog.pins.map(\.kind) == [
                .php, .caddy, .composer, .laravel, .mysql, .postgresql, .redis, .mailpit, .rustfs,
            ])
        #expect(
            catalog.pins(in: .database).map(\.id) == [
                "mysql-8.4.11-arm64", "postgresql-18.6-universal", "redis-8.8.3-arm64",
            ])
        #expect(catalog.supportSources["xz"]?.version == "5.8.4")
    }

    @Test func committedPinsKeepTheReviewedDigestsOfTheOldPinFiles() throws {
        let catalog = try committedCatalog()
        let expected: [RuntimeKind: (String, Int64)] = [
            .php: ("59761adfe93cf737282843ea1cbc74e2fef3dd86839554efd71c3dddb2b867dc", 66_723_803),
            .caddy: ("9efb0af2d6cf09cfb5053c0e51721b9b3d4956d346234f39368d943d25a3c9a7", 16_448_366),
            .composer: ("7a2d379d5b8ffdaa028580ef26494c36d2feef4b178d3dd1473a4dbc5e17c8d6", 3_642_137),
            .mysql: ("b96e00493bc3499b9ffd7f08d65c5d64933af0383a8287d9873b64f94c2d6009", 167_977_240),
            .postgresql: ("9fc7d0dc08cf46dfd94bb32cbaaad81b41b37847a42d6dcb2f9fbd292813defb", 122_517_005),
            .redis: ("13dbcfc6107ab8b6ab2a4f4582678143d5b2fd03ba38611b810359564cfe8a3c", 4_496_813),
            .mailpit: ("f72ac5bae2c8ef6bd719c1aa11237500e9a81e50ba759f92b9b1e80812920a85", 9_848_192),
            .rustfs: ("06e32a681c16930fb5414df64c96151fe3370321fab0403a83a83a015874c39a", 87_018_416),
        ]
        for (kind, (sha256, size)) in expected {
            let archive = try #require(catalog.pin(for: kind)?.archive)
            #expect(archive.sha256 == sha256 && archive.size == size, "\(kind)")
        }
        #expect(
            catalog.pin(for: .mysql)?.signature?.sha256
                == "7ae5895cfa44a930e7bb07fbc3cdaac0488997e56ae6b0d6e0733161bc506d03")
    }

    @Test func committedLaravelLockMatchesItsPin() throws {
        let pin = try #require(try committedCatalog().pin(for: .laravel))
        let project = try #require(pin.composerProject)
        let lock = project.directory.url(in: Fixture.repositoryFile("Runtimes")).appendingPathComponent("composer.lock")
        #expect(try FileDigest.hexSHA256(of: lock) == project.lockSHA256)
        #expect(pin.artifactSHA256 == project.lockSHA256)
    }

    @Test func catalogsThatBreakARuleAreRefused() throws {
        let catalog = try committedCatalog()
        let pins = catalog.pins
        let duplicate = RuntimePinCatalog(architecture: .arm64, pins: pins + [pins[0]])
        #expect(throws: JerdError.self) { try duplicate.validate() }
        let url = try #require(URL(string: "https://example.com/a.tar.gz"))
        let page = try #require(URL(string: "https://example.com"))
        let cases = [
            RuntimePin(id: "../x", kind: .php, version: "8.5.11", archive: archive(url), releasePage: page),
            RuntimePin(id: "x", kind: .php, version: "8.5", archive: nil, releasePage: page),
            RuntimePin(
                id: "x", kind: .redis, version: "8.8.3", archive: archive(url),
                signature: PinnedFile(url: url, sizeLimit: 10, sha256: digest("a")), releasePage: page),
            RuntimePin(id: "x", kind: .cloudflared, version: "2026.9.3", archive: archive(url), releasePage: page),
            RuntimePin(
                id: "x", kind: .php, version: "8.5.11",
                archive: PinnedArchive(url: url, size: 0, sha256: digest("a")), releasePage: page),
            RuntimePin(id: "x", kind: .laravel, version: "5.32.0", archive: archive(url), releasePage: page),
        ]
        for pin in cases {
            #expect(throws: JerdError.self, "\(pin.id) \(pin.kind)") { try pin.validate() }
        }
    }

    @Test func unreadableCatalogsAreRefused() {
        #expect(throws: JerdError.self) { try RuntimePinCatalog.decode(Data("{}".utf8)) }
        #expect(throws: JerdError.invalid("The runtime pin catalog is too large.")) {
            try RuntimePinCatalog.decode(Data(count: RuntimePinCatalog.sizeLimit + 1))
        }
    }

    @Test func committedCatalogEmbedsEveryGroupExceptTheDatabaseRuntimes() throws {
        let catalog = try committedCatalog()
        #expect(catalog.embeddedGroups == [.development, .mail, .storage])
        #expect(!catalog.isEmbedded(.database))
        #expect(catalog.onDemandPins.map(\.kind) == [.mysql, .postgresql, .redis])
        #expect(catalog.groups?["xz"] == PayloadGroupSettings(embedded: false))
    }

    @Test func catalogWithoutGroupSettingsEmbedsEveryGroup() throws {
        let committed = try committedCatalog()
        let old = RuntimePinCatalog(
            architecture: .arm64, pins: committed.pins, supportSources: committed.supportSources)
        #expect(old.embeddedGroups == PayloadGroup.allCases)
        #expect(old.onDemandPins.isEmpty)
        let encoded = try JSONEncoder().encode(old)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("\"groups\""))
        #expect(try RuntimePinCatalog.decode(encoded) == old)
    }

    /// The fields that every earlier reader decodes. Unknown keys such as `groups` are ignored.
    private struct EarlierCatalog: Decodable {
        let schemaVersion: Int
        let architecture: CPUArchitecture
        let pins: [RuntimePin]
        let supportSources: [String: PinnedSupportSource]
    }

    @Test func earlierReadersStillReadTheCommittedCatalog() throws {
        let data = try Data(contentsOf: Fixture.repositoryFile("Runtimes/runtimes.json"))
        let earlier = try JSONDecoder().decode(EarlierCatalog.self, from: data)
        #expect(earlier.schemaVersion == 1 && earlier.architecture == .arm64)
        #expect(earlier.pins == (try committedCatalog().pins) && earlier.supportSources["xz"] != nil)
    }

    @Test func groupSettingsThatBreakARuleAreRefused() throws {
        let committed = try committedCatalog()
        let complete = try #require(committed.groups)
        var missing = complete
        missing["mail"] = nil
        var unknown = complete
        unknown["tools"] = PayloadGroupSettings(embedded: true)
        var embeddedSupport = complete
        embeddedSupport["xz"] = PayloadGroupSettings(embedded: true)
        for groups in [missing, unknown, embeddedSupport] {
            let catalog = RuntimePinCatalog(
                architecture: .arm64, pins: committed.pins, supportSources: committed.supportSources, groups: groups)
            #expect(throws: JerdError.self, "\(groups.keys.sorted())") { try catalog.validate() }
        }
    }

    private func archive(_ url: URL) -> PinnedArchive { PinnedArchive(url: url, size: 10, sha256: digest("a")) }
}
