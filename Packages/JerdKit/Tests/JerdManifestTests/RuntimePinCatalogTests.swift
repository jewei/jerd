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

    @Test func committedCatalogEmbedsEveryPayloadExceptMySQLAndPostgreSQL() throws {
        let catalog = try committedCatalog()
        #expect(catalog.onDemandPins.map(\.kind) == [.mysql, .postgresql])
        #expect(
            catalog.embeddedPins.map(\.kind) == [.php, .caddy, .composer, .laravel, .redis, .mailpit, .rustfs])
        // Redis stays embedded: the database group is partly embedded.
        #expect(catalog.embeddedPins.filter { $0.group == .database }.map(\.kind) == [.redis])
    }

    @Test func committedPostgreSQLPinNamesItsEngineVersion() throws {
        let pin = try #require(try committedCatalog().pin(for: .postgresql))
        #expect(pin.version == "2.9.6" && pin.engineVersion == "18.6" && pin.displayVersion == "18.6")
        #expect(try committedCatalog().pin(for: .mysql)?.displayVersion == "8.4.11")
    }

    @Test func onDemandPinsStateTheirInstalledSize() throws {
        let catalog = try committedCatalog()
        #expect(catalog.pin(for: .mysql)?.installedSize == 360_498_219)
        #expect(catalog.pin(for: .postgresql)?.installedSize == 753_446_725)
        let page = try #require(URL(string: "https://example.com"))
        let url = try #require(URL(string: "https://example.com/a.tar.gz"))
        for size in [Int64(0), RuntimePin.installedSizeLimit + 1] {
            let pin = RuntimePin(
                id: "x", kind: .mysql, version: "8.4.11", archive: archive(url),
                signature: PinnedFile(url: url, sizeLimit: 10, sha256: digest("a")), releasePage: page,
                embedded: false, installedSize: size)
            #expect(throws: JerdError.self, "\(size)") { try pin.validate() }
        }
    }

    @Test func pinWithoutTheNewFieldsIsEmbeddedAndKeepsItsEncoding() throws {
        let committed = try committedCatalog()
        let pins = committed.pins.map {
            RuntimePin(
                id: $0.id, kind: $0.kind, version: $0.version, archive: $0.archive, signature: $0.signature,
                composerProject: $0.composerProject, releasePage: $0.releasePage)
        }
        let old = RuntimePinCatalog(architecture: .arm64, pins: pins, supportSources: committed.supportSources)
        #expect(old.onDemandPins.isEmpty && old.embeddedPins.count == pins.count)
        let encoded = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        #expect(!encoded.contains("\"embedded\"") && !encoded.contains("\"engineVersion\""))
        #expect(try RuntimePinCatalog.decode(Data(encoded.utf8)) == old)
    }

    /// The fields that every earlier reader decodes. Unknown keys such as `embedded` are ignored.
    private struct EarlierPin: Decodable {
        let id: String
        let kind: RuntimeKind
        let version: String
        let archive: PinnedArchive?
    }

    private struct EarlierCatalog: Decodable {
        let schemaVersion: Int
        let architecture: CPUArchitecture
        let pins: [EarlierPin]
        let supportSources: [String: PinnedSupportSource]
    }

    @Test func earlierReadersStillReadTheCommittedCatalog() throws {
        let data = try Data(contentsOf: Fixture.repositoryFile("Runtimes/runtimes.json"))
        let earlier = try JSONDecoder().decode(EarlierCatalog.self, from: data)
        #expect(earlier.schemaVersion == 1 && earlier.architecture == .arm64)
        #expect(earlier.pins.map(\.id) == (try committedCatalog().pins.map(\.id)))
        #expect(earlier.pins.first { $0.kind == .postgresql }?.version == "2.9.6")
    }

    @Test func onDemandAndEngineVersionRulesAreEnforced() throws {
        let page = try #require(URL(string: "https://example.com"))
        let project = PinnedComposerProject(
            directory: try #require(RelativePath("laravel-installer")), lockSHA256: digest("c"))
        let laravel = RuntimePin(
            id: "x", kind: .laravel, version: "5.32.0", archive: nil, composerProject: project, releasePage: page,
            embedded: false)
        #expect(throws: JerdError.self) { try laravel.validate() }
        let url = try #require(URL(string: "https://example.com/a.tar.gz"))
        let badEngine = RuntimePin(
            id: "x", kind: .postgresql, version: "2.9.6", archive: archive(url), releasePage: page,
            engineVersion: "eighteen")
        #expect(throws: JerdError.self) { try badEngine.validate() }
    }

    private func archive(_ url: URL) -> PinnedArchive { PinnedArchive(url: url, size: 10, sha256: digest("a")) }
}
