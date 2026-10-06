import Foundation
import JerdManifest
import Testing

@testable import JerdDevKit

@Suite("Release inputs and version rules")
struct ReleaseInputsTests {
    static func item(build: String, version: String?) -> AppcastItem {
        AppcastItem(
            title: nil, bundleVersion: build, shortVersion: version, minimumSystemVersion: "14.0",
            hardwareRequirements: "arm64",
            enclosure: AppcastEnclosure(
                url: URL(string: "https://example.com/a.dmg")!, length: 1, signature: Data(count: 64)))
    }

    @Test("Versions compare with missing parts as zero")
    func versionsCompare() throws {
        #expect(ReleaseVersion("1.0") == ReleaseVersion("1.0.0"))
        #expect(try #require(ReleaseVersion("0.10.0")) > #require(ReleaseVersion("0.9.9")))
        #expect(ReleaseVersion.release("1") == nil)
        #expect(ReleaseVersion.release("1.2.3.4.5") == nil)
        for bad in ["1..0", "1.a", "-1.0", "1.0 ", ""] {
            #expect(ReleaseVersion(bad) == nil)
        }
    }

    @Test("Builds are positive integers without a leading zero")
    func buildsAreChecked() {
        #expect(ReleaseVersion.build("3") == 3)
        for bad in ["0", "03", "-1", "1.0", "", "x"] {
            #expect(ReleaseVersion.build(bad) == nil)
        }
    }

    @Test("Inputs need an explicit minimum macOS, a team ID, and a notary profile")
    func inputsAreChecked() throws {
        let inputs = try ReleaseInputs.parse(
            version: "0.2.0", build: "3", minimumMacOS: "14.0", identity: ReleaseFixtures.identity,
            team: ReleaseFixtures.team, notaryProfile: "notary", keychain: nil)
        #expect(inputs.minimumMacOS.text == "14.0")
        #expect(inputs.notary.arguments == ["--keychain-profile", "notary"])
        let failures: [() throws -> ReleaseInputs] = [
            {
                try .parse(
                    version: "0.2", build: "3", minimumMacOS: "x", identity: "I", team: "ABCDE12345",
                    notaryProfile: "p", keychain: nil)
            },
            {
                try .parse(
                    version: "0.2", build: "3", minimumMacOS: "14", identity: "I", team: "abc",
                    notaryProfile: "p", keychain: nil)
            },
            {
                try .parse(
                    version: "0.2", build: "3", minimumMacOS: "14", identity: "", team: "ABCDE12345",
                    notaryProfile: "p", keychain: nil)
            },
            {
                try .parse(
                    version: "0.2", build: "3", minimumMacOS: "14", identity: "I", team: "ABCDE12345",
                    notaryProfile: "p", keychain: "relative")
            },
        ]
        for failure in failures {
            #expect(throws: DevFailure.self) { try failure() }
        }
    }

    @Test("The notary arguments include the Keychain only when it is given")
    func notaryArguments() throws {
        let credentials = try NotaryCredentials(profile: "p", keychain: "/k.keychain-db")
        #expect(credentials.arguments == ["--keychain-profile", "p", "--keychain", "/k.keychain-db"])
    }

    @Test("The Developer ID requirement names the team and the Developer ID marker")
    func requirementNamesTheTeam() throws {
        let identity = try SigningIdentity(identity: "I", team: ReleaseFixtures.team)
        #expect(SigningIdentity.requirement(team: identity.team).hasPrefix("=anchor apple generic"))
        #expect(SigningIdentity.requirement(team: identity.team).contains("leaf[subject.OU] = \"ABCDE12345\""))
        #expect(SigningIdentity.requirement(team: identity.team).contains("field.1.2.840.113635.100.6.1.13"))
    }

    @Test("A release must exceed every published build and version")
    func feedRules() throws {
        let version = try #require(ReleaseVersion.release("0.2.0"))
        try VersionRules.checkFeed(version: version, build: 3, items: [])
        try VersionRules.checkFeed(version: version, build: 3, items: [Self.item(build: "2", version: "0.1.0")])
        let refused = [
            Self.item(build: "3", version: "0.1.0"), Self.item(build: "2", version: "0.2.0"),
            Self.item(build: "x", version: "0.1.0"), Self.item(build: "2", version: nil),
        ]
        for item in refused {
            #expect(throws: DevFailure.self) { try VersionRules.checkFeed(version: version, build: 3, items: [item]) }
        }
    }

    @Test("A bump raises the build and keeps or raises the version")
    func bumpRules() throws {
        let version = try #require(ReleaseVersion.release("0.1.0"))
        try VersionRules.checkBump(version: version, build: 3, current: ("0.1.0", "2"), items: [])
        #expect(throws: DevFailure.self) {
            try VersionRules.checkBump(version: version, build: 2, current: ("0.1.0", "2"), items: [])
        }
        #expect(throws: DevFailure.self) {
            try VersionRules.checkBump(version: version, build: 3, current: ("0.2.0", "2"), items: [])
        }
    }

    @Test("Preparation requires the version of the source commit")
    func sourceRule() throws {
        let version = try #require(ReleaseVersion.release("0.2.0"))
        try VersionRules.checkSource(version: version, build: 3, file: ("0.2.0", "3"))
        #expect(throws: DevFailure.self) {
            try VersionRules.checkSource(version: version, build: 3, file: ("0.1.0", "3"))
        }
        #expect(throws: DevFailure.self) {
            try VersionRules.checkSource(version: version, build: 4, file: ("0.2.0", "3"))
        }
    }
}
