import Foundation
import Testing

@testable import JerdDevKit

@Suite("Sparkle Info.plist policy")
struct SparkleInfoPlistPolicyTests {
    /// The committed `Apps/Jerd/Resources/Info.plist`.
    static let committedPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        	<key>SUFeedURL</key>
        	<string>$(JERD_UPDATE_FEED_URL)</string>
        	<key>SUPublicEDKey</key>
        	<string>$(JERD_UPDATE_PUBLIC_KEY)</string>
        	<key>SUAutomaticallyUpdate</key>
        	<false/>
        	<key>SUAllowsAutomaticUpdates</key>
        	<false/>
        	<key>SUEnableSystemProfiling</key>
        	<false/>
        	<key>SUVerifyUpdateBeforeExtraction</key>
        	<true/>
        	<key>SURequireSignedFeed</key>
        	<true/>
        	<key>SUSignedFeedFailureExpirationInterval</key>
        	<integer>0</integer>
        </dict>
        </plist>
        """

    private func findings(_ plist: String) -> [String] {
        SparkleInfoPlistPolicy.findings(plistData: Data(plist.utf8)).map(\.message)
    }

    @Test("accepts the committed Info.plist")
    func acceptsCommittedPlist() {
        #expect(findings(Self.committedPlist).isEmpty)
    }

    @Test("checks eight keys and keeps the automatic check key absent")
    func checksKeys() {
        #expect(SparkleInfoPlistPolicy.requiredValues.count == 8)
        #expect(SparkleInfoPlistPolicy.absentKeys == ["SUEnableAutomaticChecks"])
    }

    @Test("reports a changed value")
    func reportsChangedValue() {
        let plist = Self.committedPlist.replacingOccurrences(
            of: "<key>SUAutomaticallyUpdate</key>\n\t<false/>", with: "<key>SUAutomaticallyUpdate</key>\n\t<true/>")
        #expect(findings(plist) == ["SUAutomaticallyUpdate has boolean true; it must be boolean false."])
    }

    @Test(
        "reports the automatic check key with any value, so Sparkle can ask the user",
        arguments: ["<false/>", "<true/>"])
    func reportsAutomaticCheckKey(value: String) {
        let plist = Self.committedPlist.replacingOccurrences(
            of: "</dict>", with: "\t<key>SUEnableAutomaticChecks</key>\n\t\(value)\n</dict>")
        #expect(
            findings(plist) == ["SUEnableAutomaticChecks must be absent, so Sparkle asks the user whether to check."])
    }

    @Test("the committed Info.plist has no automatic check key")
    func committedFileHasNoAutomaticCheckKey() throws {
        let url = ReleaseFixtures.repositoryRoot.appending(path: SparkleInfoPlistPolicy.file)
        #expect(SparkleInfoPlistPolicy.findings(plistData: try Data(contentsOf: url)).isEmpty)
    }

    @Test("reports a value of the wrong type, even when it means the same")
    func reportsWrongType() {
        let plist = Self.committedPlist.replacingOccurrences(of: "<integer>0</integer>", with: "<false/>")
        #expect(
            findings(plist) == ["SUSignedFeedFailureExpirationInterval has boolean false; it must be integer 0."])
    }

    @Test("reports a missing key and an unapproved Sparkle key")
    func reportsMissingAndExtraKeys() {
        let plist = Self.committedPlist
            .replacingOccurrences(of: "\t<key>SURequireSignedFeed</key>\n\t<true/>\n", with: "")
            .replacingOccurrences(
                of: "</dict>", with: "\t<key>SUScheduledCheckInterval</key>\n\t<integer>3600</integer>\n</dict>")
        #expect(
            findings(plist) == [
                "SURequireSignedFeed is missing; it must be boolean true.",
                "SUScheduledCheckInterval is not an approved Sparkle setting.",
            ])
    }

    @Test("reports a file that is not a property list")
    func reportsInvalidFile() {
        #expect(findings("not a plist") == ["The file is not a property list dictionary."])
    }
}
