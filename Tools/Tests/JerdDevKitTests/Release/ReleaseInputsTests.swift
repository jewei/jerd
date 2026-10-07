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

    @Test("The minimum macOS defaults to the deployment target and may not be older")
    func minimumMacOS() throws {
        let inputs = try ReleaseFixtures.inputs(minimum: nil)
        #expect(inputs.minimumMacOS.text == "14.0")
        #expect(inputs.notary.arguments == ["--keychain-profile", "notary"])
        #expect(inputs.signing.identity == ReleaseFixtures.sha1)
        #expect(try ReleaseFixtures.inputs(minimum: "15.1").minimumMacOS.text == "15.1")
        #expect(throws: DevFailure.self) { try ReleaseFixtures.inputs(minimum: "13.5") }
    }

    @Test("The form check refuses a bad version, build, minimum, team, identity, and Keychain path")
    func formIsChecked() throws {
        try ReleaseInputs.checkForm(ReleaseFixtures.request())
        var requests: [ReleaseRequest] = []
        for change in [
            { (r: inout ReleaseRequest) in r.version = "1" }, { $0.version = "0.2.x" }, { $0.build = "03" },
            { $0.build = "0" }, { $0.minimumMacOS = "x" }, { $0.team = "abc" }, { $0.identity = "" },
            { $0.keychain = "relative" }, { $0.notaryProfile = "-p" },
        ] as [(inout ReleaseRequest) -> Void] {
            var request = ReleaseFixtures.request()
            change(&request)
            requests.append(request)
        }
        for request in requests {
            #expect(throws: DevFailure.self) { try ReleaseInputs.checkForm(request) }
        }
    }

    @Test("Without --identity the only Developer ID identity of the team is selected by SHA-1")
    func selectsDefaultIdentity() throws {
        let identity = try SigningIdentity.select(
            nil, team: ReleaseFixtures.team, identities: ReleaseFixtures.identities)
        #expect(identity.identity == ReleaseFixtures.sha1 && identity.name == ReleaseFixtures.identity)
        let lower = try SigningIdentity.select(
            ReleaseFixtures.sha1.lowercased(), team: ReleaseFixtures.team, identities: ReleaseFixtures.identities)
        #expect(lower.identity == ReleaseFixtures.sha1)
        let named = try SigningIdentity.select(
            ReleaseFixtures.identity, team: ReleaseFixtures.team, identities: ReleaseFixtures.identities)
        #expect(named.identity == ReleaseFixtures.sha1)
    }

    @Test("Two certificates with the same name need a SHA-1, and a missing identity is a missing prerequisite")
    func refusesAmbiguousIdentity() throws {
        let two = ReleaseFixtures.identities + "  3) \(ReleaseFixtures.otherSHA1) \"\(ReleaseFixtures.identity)\"\n"
        let error = #expect(throws: DevFailure.self) {
            try SigningIdentity.select(nil, team: ReleaseFixtures.team, identities: two)
        }
        #expect(error?.status == .usage && error?.message.contains(ReleaseFixtures.otherSHA1) == true)
        let chosen = try SigningIdentity.select(ReleaseFixtures.otherSHA1, team: ReleaseFixtures.team, identities: two)
        #expect(chosen.identity == ReleaseFixtures.otherSHA1)
        let missing = #expect(throws: DevFailure.self) {
            try SigningIdentity.select(nil, team: "QQQQQ11111", identities: ReleaseFixtures.identities)
        }
        #expect(missing?.status == .missingPrerequisite)
        #expect(throws: DevFailure.self) {
            try SigningIdentity.select(
                "FEDCBA9876543210FEDCBA9876543210FEDCBA98", team: ReleaseFixtures.team,
                identities: ReleaseFixtures.identities)
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

    @Test("A release keeps or raises the version file values, and a released build must grow")
    func projectRules() throws {
        let version = try #require(ReleaseVersion.release("0.1.0"))
        try VersionRules.checkProject(version: version, build: 2, current: ("0.1.0", "2"), currentIsTagged: false)
        try VersionRules.checkProject(version: version, build: 3, current: ("0.1.0", "2"), currentIsTagged: true)
        #expect(throws: DevFailure.self) {
            try VersionRules.checkProject(version: version, build: 2, current: ("0.1.0", "2"), currentIsTagged: true)
        }
        #expect(throws: DevFailure.self) {
            try VersionRules.checkProject(version: version, build: 1, current: ("0.1.0", "2"), currentIsTagged: false)
        }
        #expect(throws: DevFailure.self) {
            try VersionRules.checkProject(version: version, build: 3, current: ("0.2.0", "2"), currentIsTagged: false)
        }
    }
}
