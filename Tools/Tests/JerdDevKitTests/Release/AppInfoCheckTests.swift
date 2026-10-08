import Foundation
import JerdManifest
import Testing

@testable import JerdDevKit

@Suite("Release app Info.plist")
struct AppInfoCheckTests {
    static let check = AppInfoCheck(
        minimumMacOS: ReleaseVersion("14.0")!, version: ReleaseVersion.release("0.2.0")!, build: 3)

    static func info() -> [String: Any] {
        [
            "CFBundleIdentifier": "dev.jerd.app", "SUFeedURL": AppUpdateSettings.officialFeedURL,
            "SUPublicEDKey": AppUpdateSettings.officialPublicKey,
            "SUAutomaticallyUpdate": false, "SUAllowsAutomaticUpdates": false, "SUEnableSystemProfiling": false,
            "SUVerifyUpdateBeforeExtraction": true, "SURequireSignedFeed": true,
            "SUSignedFeedFailureExpirationInterval": 0, "LSMinimumSystemVersion": "14.0",
            "CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "3",
        ]
    }

    @Test("Accepts the official settings and the release version")
    func accepts() throws {
        try Self.check.check(Self.info())
    }

    @Test("Refuses each wrong value, also the keys that the old release did not check")
    func refuses() {
        let changes: [(String, Any)] = [
            ("CFBundleIdentifier", "dev.jerd.other"), ("SUFeedURL", "https://example.com/appcast.xml"),
            ("SUPublicEDKey", "AAAA"), ("SUEnableAutomaticChecks", true), ("SUEnableAutomaticChecks", false),
            ("SUAutomaticallyUpdate", true),
            ("SUEnableSystemProfiling", true), ("SUSignedFeedFailureExpirationInterval", 60),
            ("SURequireSignedFeed", 1), ("LSMinimumSystemVersion", "27.0.1"), ("CFBundleVersion", "2"),
            ("CFBundleShortVersionString", "0.1.0"),
        ]
        for (key, value) in changes {
            var info = Self.info()
            info[key] = value
            #expect(throws: DevFailure.self, "\(key)") { try Self.check.check(info) }
        }
    }
}
