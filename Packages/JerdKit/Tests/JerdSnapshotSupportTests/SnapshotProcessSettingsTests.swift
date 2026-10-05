import Testing

@testable import JerdSnapshotSupport

@Suite("Snapshot process settings")
struct SnapshotProcessSettingsTests {
    @Test("The fixed values replace the accent, highlight, scroll bar, sidebar, and region settings of the user")
    func replacesUserSettings() {
        let user: [String: Any] = [
            "AppleAccentColor": 0, "AppleHighlightColor": "1 0 0 Red", "AppleShowScrollBars": "Always",
            "NSTableViewDefaultSizeMode": 3, "AppleLocale": "fr_FR", "AppleInterfaceStyle": "Dark",
        ]
        let domain = SnapshotProcessSettings.argumentDomain(merging: user, contrast: .standard)
        #expect(domain["AppleAccentColor"] as? Int == 4)
        #expect(domain["AppleHighlightColor"] as? String == "0.698039 0.843137 1.000000 Blue")
        #expect(domain["AppleShowScrollBars"] as? String == "WhenScrolling")
        #expect(domain["NSTableViewDefaultSizeMode"] as? Int == 2)
        #expect(domain["AppleLocale"] as? String == "en_US")
        #expect(domain["AppleInterfaceStyle"] as? String == "Light")
    }

    @Test("Other arguments stay in the argument domain")
    func keepsOtherArguments() {
        let domain = SnapshotProcessSettings.argumentDomain(merging: ["NSDebugSomething": true], contrast: .standard)
        #expect(domain["NSDebugSomething"] as? Bool == true)
    }

    @Test("Increase Contrast is on only for the contrast pass", arguments: SnapshotContrast.allCases)
    func contrastSetting(contrast: SnapshotContrast) {
        let domain = SnapshotProcessSettings.argumentDomain(merging: ["increaseContrast": true], contrast: contrast)
        #expect(domain["increaseContrast"] as? Bool == (contrast == .increased))
    }
}
