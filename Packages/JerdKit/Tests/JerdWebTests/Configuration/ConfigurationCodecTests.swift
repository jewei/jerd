import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct ConfigurationCodecTests {
    @Test func theOldGoldenFileDecodesAndReencodesToTheSameBytes() throws {
        let bytes = try Fixture.data("configuration/configuration-v1.json")
        let configuration = try ConfigurationCodec.decode(bytes)
        #expect(try ConfigurationCodec.encode(configuration) == bytes)
        #expect(configuration.sites[1].phpSelection == .pinned(Samples.runtimeID))
        #expect(configuration.sites[0].phpSelection == .followDefault)
        #expect(configuration.runtimes[0].inspectedAt == Date(timeIntervalSinceReferenceDate: 800_000_000.5))
        #expect(configuration.runtimes[0].architectures == [.arm64, .x86_64])
    }

    @Test func anEmptyConfigurationKeepsTheOldEncodingWithoutOptionalKeys() throws {
        let bytes = try ConfigurationCodec.encode(AppConfiguration())
        #expect(bytes == (try Fixture.data("configuration/configuration-empty.json")))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("defaultRuntimeID"))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("caddy"))
    }

    @Test func versionZeroMigratesToVersionOneInMemory() throws {
        let configuration = try ConfigurationCodec.decode(try Fixture.data("configuration/configuration-v0.json"))
        #expect(configuration.schemaVersion == 1)
        #expect(configuration.sites.map(\.hostname) == ["legacy.test"])
        #expect(configuration.runtimes.isEmpty)
        #expect(configuration.defaultRuntimeID == nil)
    }

    @Test(arguments: [2, 999, -1])
    func anUnsupportedVersionIsCorrupt(_ version: Int) {
        let data = Data("{\"schemaVersion\":\(version),\"sites\":[]}".utf8)
        #expect(throws: JerdError.corrupt("Unsupported configuration version: \(version).")) {
            try ConfigurationCodec.decode(data)
        }
    }

    @Test func aMissingVersionIsADecodingError() {
        #expect(throws: DecodingError.self) { try ConfigurationCodec.decode(Data("{\"sites\":[]}".utf8)) }
    }

    @Test(arguments: StructureCase.allCases)
    func structureRulesRejectInvalidRecords(_ rule: StructureCase) {
        #expect(throws: rule.error) { try ConfigurationCodec.validate(rule.configuration) }
    }

    @Test func aValidConfigurationPassesTheStructureRules() throws {
        let site = Samples.site(URL(fileURLWithPath: "/p/app"), documentRoot: URL(fileURLWithPath: "/p/app/public"))
        try ConfigurationCodec.validate(Samples.configuration([site]))
    }
}

/// One broken configuration for each structure rule.
enum StructureCase: CaseIterable, Sendable {
    case wrongVersion, duplicateSiteID, duplicateHostname, duplicateProject, duplicateRuntimeID
    case invalidHostname, relativeProject, relativeRoot, rootOutsideProject

    var configuration: AppConfiguration {
        let first = Samples.site(URL(fileURLWithPath: "/p/one"), hostname: "one.test")
        let second = Samples.site(URL(fileURLWithPath: "/p/two"), hostname: "two.test")
        var configuration = Samples.configuration([first, second])
        switch self {
        case .wrongVersion: configuration.schemaVersion = 0
        case .duplicateSiteID: configuration.sites[1].id = first.id
        case .duplicateHostname: configuration.sites[1].hostname = "ONE.test"
        case .duplicateProject: configuration.sites[1].projectPath = "/p/one"
        case .duplicateRuntimeID: configuration.runtimes.append(configuration.runtimes[0])
        case .invalidHostname: configuration.sites[1].hostname = "two.com"
        case .relativeProject: configuration.sites[1].projectPath = "p/two"
        case .relativeRoot: configuration.sites[1].documentRoot = "p/two"
        case .rootOutsideProject: configuration.sites[1].documentRoot = "/p/twofold"
        }
        return configuration
    }

    var error: JerdError {
        switch self {
        case .wrongVersion, .duplicateSiteID, .duplicateHostname, .duplicateProject, .duplicateRuntimeID:
            .corrupt("Configuration contains an invalid version or duplicate records.")
        case .invalidHostname:
            .invalid("Use a hostname ending in .test, without spaces or a port.")
        case .relativeProject, .relativeRoot, .rootOutsideProject:
            .corrupt("Configuration contains an invalid project path.")
        }
    }
}
