import Testing

@testable import JerdDevKit

@Suite("App update settings policy")
struct UpdateSettingsPolicyTests {
    /// The update lines of the committed `Configuration/App.xcconfig`.
    static let xcconfig = """
        // Sparkle reads these values through Info.plist. Installed apps depend on them.
        JERD_UPDATE_FEED_URL = https:/$()/raw.githubusercontent.com/jewei/jerd/main/appcast.xml
        JERD_UPDATE_PUBLIC_KEY = FjYzr89ynpNrTtI8Me8zqA88YYJrRmloo4bj6dLbAJA=
        JERD_REQUIRE_RUNTIMES = NO
        JERD_REQUIRE_RUNTIMES[config=Release] = YES
        """

    private func findings(_ text: String) -> [String] {
        UpdateSettingsPolicy.findings(xcconfig: text).map(\.message)
    }

    @Test("accepts the committed feed URL and key")
    func acceptsCommittedSettings() {
        #expect(findings(Self.xcconfig).isEmpty)
    }

    @Test("reads values without comments and without the empty $() escape")
    func parsesSettings() {
        let settings = UpdateSettingsPolicy.parseSettings(Self.xcconfig + "\nNAME = value // comment")
        #expect(settings["JERD_UPDATE_FEED_URL"] == UpdateSettingsPolicy.feedURL)
        #expect(settings["NAME"] == "value")
        #expect(settings["JERD_REQUIRE_RUNTIMES"] == "NO")
    }

    @Test("reports missing settings")
    func reportsMissingSettings() {
        #expect(
            findings("OTHER = 1") == [
                "JERD_UPDATE_FEED_URL is missing.", "JERD_UPDATE_PUBLIC_KEY is missing.",
            ])
    }

    @Test("reports a changed feed URL")
    func reportsChangedFeed() {
        let text = Self.xcconfig.replacingOccurrences(of: "/main/", with: "/next/")
        #expect(
            findings(text) == [
                "JERD_UPDATE_FEED_URL is https://raw.githubusercontent.com/jewei/jerd/next/appcast.xml; "
                    + "installed apps use https://raw.githubusercontent.com/jewei/jerd/main/appcast.xml."
            ])
    }

    @Test("reports a malformed key and a different valid key")
    func reportsWrongKeys() {
        let malformed = Self.xcconfig.replacingOccurrences(of: "FjYzr89y", with: "short")
        #expect(findings(malformed) == ["JERD_UPDATE_PUBLIC_KEY is not a base64 Ed25519 public key."])
        let other = Self.xcconfig.replacingOccurrences(of: "FjYzr89y", with: "AAAAAAAA")
        #expect(findings(other) == ["JERD_UPDATE_PUBLIC_KEY is not the key that installed apps trust."])
    }
}
