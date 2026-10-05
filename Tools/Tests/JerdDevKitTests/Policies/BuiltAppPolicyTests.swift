import Foundation
import Testing

@testable import JerdDevKit

@Suite("Built app policy")
struct BuiltAppPolicyTests {
    /// The Info.plist values that a correct build makes.
    static func validPlist(changing changes: [String: Any] = [:]) throws -> Data {
        var values: [String: Any] = [
            "CFBundleIdentifier": "dev.jerd.app",
            "LSMinimumSystemVersion": "14.0",
            "SUFeedURL": UpdateSettingsPolicy.feedURL,
            "SUPublicEDKey": UpdateSettingsPolicy.publicKey,
            "SUEnableAutomaticChecks": false,
            "SUAutomaticallyUpdate": false,
            "SUAllowsAutomaticUpdates": false,
            "SUEnableSystemProfiling": false,
            "SUVerifyUpdateBeforeExtraction": true,
            "SURequireSignedFeed": true,
            "SUSignedFeedFailureExpirationInterval": 0,
        ]
        values.merge(changes) { _, new in new }
        return try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
    }

    @Test("accepts the expanded feed URL, key, and Sparkle keys")
    func acceptsValidPlist() throws {
        #expect(BuiltAppPolicy.infoPlistFindings(try Self.validPlist(), file: "Info.plist").isEmpty)
    }

    @Test("refuses an effective feed URL that a conditional setting changed")
    func refusesChangedFeed() throws {
        let data = try Self.validPlist(changing: ["SUFeedURL": "https://evil.example/appcast.xml"])
        #expect(
            BuiltAppPolicy.infoPlistFindings(data, file: "Info.plist").map(\.message) == [
                "SUFeedURL has string \"https://evil.example/appcast.xml\"; "
                    + "it must be string \"\(UpdateSettingsPolicy.feedURL)\"."
            ])
    }

    @Test("refuses an unexpanded key, a wrong minimum macOS version, and a broken file")
    func refusesOtherProblems() throws {
        let data = try Self.validPlist(changing: ["SUPublicEDKey": "", "LSMinimumSystemVersion": "27.0"])
        #expect(BuiltAppPolicy.infoPlistFindings(data, file: "x").count == 2)
        #expect(
            BuiltAppPolicy.infoPlistFindings(Data("nope".utf8), file: "x").map(\.message) == [
                "The file is not a property list dictionary."
            ])
    }

    @Test("accepts only arm64 executables")
    func checksArchitectures() {
        #expect(BuiltAppPolicy.architectureFindings(file: "Jerd", lipoOutput: "arm64\n").isEmpty)
        #expect(
            BuiltAppPolicy.architectureFindings(file: "Jerd", lipoOutput: "x86_64 arm64\n").map(\.message) == [
                "The executable contains x86_64 arm64; it must contain only arm64."
            ])
        #expect(BuiltAppPolicy.architectureFindings(file: "Jerd", lipoOutput: nil).count == 1)
    }
}
