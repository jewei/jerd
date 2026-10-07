import Testing

@testable import JerdDevKit

@Suite("App update settings policy")
struct UpdateSettingsPolicyTests {
    /// The update lines of the committed `Configuration/App.xcconfig`.
    static let xcconfig = """
        #include "Base.xcconfig"
        // Sparkle reads these values through Info.plist. Installed apps depend on them.
        JERD_UPDATE_FEED_URL = https:/$()/raw.githubusercontent.com/jewei/jerd/main/appcast.xml
        JERD_UPDATE_PUBLIC_KEY = FjYzr89ynpNrTtI8Me8zqA88YYJrRmloo4bj6dLbAJA=
        JERD_REQUIRE_RUNTIMES = NO
        JERD_REQUIRE_RUNTIMES[config=Release] = YES
        """

    static let base = """
        SWIFT_VERSION = 6.0
        ARCHS = arm64
        """

    static let projectSpec = """
        targets:
          Jerd:
            configFiles:
              Release: Configuration/App.xcconfig
        """

    private func findings(app: String = xcconfig, base: String = base, spec: String = projectSpec) -> [String] {
        let files = [
            (path: "Configuration/App.xcconfig", text: app), (path: "Configuration/Base.xcconfig", text: base),
        ]
        return UpdateSettingsPolicy.findings(xcconfigs: files, projectSpec: spec).map(\.description)
    }

    @Test("accepts the committed feed URL and key")
    func acceptsCommittedSettings() {
        #expect(findings().isEmpty)
    }

    @Test("reads values without comments and without the empty $() escape, and marks conditions")
    func parsesSettings() {
        let assignments = UpdateSettingsPolicy.assignments(in: Self.xcconfig + "\nNAME = value // comment")
        #expect(assignments.first?.value == UpdateSettingsPolicy.feedURL)
        #expect(assignments.contains(.init(name: "NAME", isConditional: false, value: "value")))
        #expect(assignments.contains(.init(name: "JERD_REQUIRE_RUNTIMES", isConditional: true, value: "YES")))
        #expect(!assignments.contains { $0.name.hasPrefix("#") })
    }

    @Test("reports missing settings")
    func reportsMissingSettings() {
        #expect(
            findings(app: "OTHER = 1") == [
                "Configuration/App.xcconfig: JERD_UPDATE_FEED_URL is missing.",
                "Configuration/App.xcconfig: JERD_UPDATE_PUBLIC_KEY is missing.",
            ])
    }

    @Test("reports a changed feed URL")
    func reportsChangedFeed() {
        let text = Self.xcconfig.replacingOccurrences(of: "/main/", with: "/next/")
        #expect(
            findings(app: text) == [
                "Configuration/App.xcconfig: JERD_UPDATE_FEED_URL is "
                    + "https://raw.githubusercontent.com/jewei/jerd/next/appcast.xml; "
                    + "installed apps use https://raw.githubusercontent.com/jewei/jerd/main/appcast.xml."
            ])
    }

    @Test("reports a malformed key and a different valid key")
    func reportsWrongKeys() {
        let malformed = Self.xcconfig.replacingOccurrences(of: "FjYzr89y", with: "short")
        #expect(
            findings(app: malformed) == [
                "Configuration/App.xcconfig: JERD_UPDATE_PUBLIC_KEY is not a base64 Ed25519 public key."
            ])
        let other = Self.xcconfig.replacingOccurrences(of: "FjYzr89y", with: "AAAAAAAA")
        #expect(
            findings(app: other) == [
                "Configuration/App.xcconfig: JERD_UPDATE_PUBLIC_KEY is not the key that installed apps trust."
            ])
    }

    @Test(
        "refuses a conditional assignment of either name in any xcconfig",
        arguments: [
            "JERD_UPDATE_FEED_URL[config=Release] = https:/$()/evil.example/appcast.xml",
            "JERD_UPDATE_PUBLIC_KEY[sdk=macosx*] = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
            "JERD_UPDATE_FEED_URL [arch=arm64] = https:/$()/evil.example/appcast.xml",
        ])
    func refusesConditionalAssignments(line: String) {
        let name = line.hasPrefix("JERD_UPDATE_FEED_URL") ? "JERD_UPDATE_FEED_URL" : "JERD_UPDATE_PUBLIC_KEY"
        let expected = "\(name) has a conditional assignment; only one plain assignment is allowed."
        #expect(findings(app: Self.xcconfig + "\n" + line) == ["Configuration/App.xcconfig: \(expected)"])
        #expect(findings(base: Self.base + "\n" + line) == ["Configuration/Base.xcconfig: \(expected)"])
    }

    @Test("refuses an overriding assignment in another xcconfig and a second one in App.xcconfig")
    func refusesOverrides() {
        let override = "JERD_UPDATE_FEED_URL = https:/$()/evil.example/appcast.xml"
        #expect(
            findings(base: Self.base + "\n" + override) == [
                "Configuration/Base.xcconfig: JERD_UPDATE_FEED_URL must be set only in Configuration/App.xcconfig."
            ])
        #expect(
            findings(app: Self.xcconfig + "\n" + override).first
                == "Configuration/App.xcconfig: JERD_UPDATE_FEED_URL is set 2 times; set it once.")
    }

    @Test("refuses the names and the Info.plist keys in project.yml, and the keys in an xcconfig")
    func refusesProjectSettings() {
        let spec = Self.projectSpec + "\n    settings:\n      INFOPLIST_KEY_SUFeedURL: https://evil.example"
        #expect(
            findings(spec: spec) == [
                "project.yml: SUFeedURL must not appear here; set it only in Configuration/App.xcconfig."
            ])
        let spec2 = Self.projectSpec + "\n    settings:\n      JERD_UPDATE_PUBLIC_KEY: x"
        #expect(findings(spec: spec2).count == 1)
        #expect(
            findings(base: "INFOPLIST_KEY_SUPublicEDKey = x") == [
                "Configuration/Base.xcconfig: SUPublicEDKey must come only from Info.plist and Configuration/App.xcconfig."
            ])
    }

    @Test("refuses an include of a file outside Configuration")
    func refusesOutsideIncludes() {
        #expect(
            findings(base: "#include? \"../Local.xcconfig\"") == [
                "Configuration/Base.xcconfig: #include \"../Local.xcconfig\" leaves Configuration/."
            ])
    }
}
