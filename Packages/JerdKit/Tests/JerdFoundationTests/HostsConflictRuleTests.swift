import Foundation
import JerdFoundation
import Testing

/// Regression test: one hosts rule for the app check and the helper.
///
/// The app rule of old builds (`HostsFile.hasConflict`) accepted `::1` and any `127.0.0.1` line
/// inside the markers, also an unpaired BEGIN marker. The helper rule (`HostsDocument`) accepted only
/// an exact section of `127.0.0.1 <name>` lines. The helper rule wins: it is the writer, and a section
/// that it refuses to replace cannot be Jerd's own.
@Suite struct HostsConflictRuleTests {
    private func conflict(_ text: String, _ hostname: String = "shop.test") -> Bool {
        HostsConflictRule.hasConflict(hostname: hostname, in: Data(text.utf8))
    }

    /// Every case of the old app rule. Both rules agree on these.
    @Test(arguments: [
        ("127.0.0.1 shop.test # another tool", true),
        ("10.0.0.2 alias SHOP.test", true),
        ("# shop.test\n127.0.0.1 other.test", false),
        ("# BEGIN JERD\n127.0.0.1 shop.test\n# END JERD", false),
        ("# BEGIN JERD\n10.1.1.1 shop.test\n# END JERD", true),
        ("# BEGIN JERD\n127.0.0.1 x.test\n# END JERD\n127.0.0.1 shop.test", true),
        ("127.0.0.1\tother.test\tshop.test", true),
        ("shop.test", false),
        ("127.0.0.1 shop.test.example", false),
        ("127.0.0.1 x.test #shop.test", false),
        ("# BEGIN JERD\r\n127.0.0.1 shop.test\r\n# END JERD", false),
        (" # BEGIN JERD\n127.0.0.1 shop.test\n# END JERD", true),
    ])
    func casesOnWhichBothOldRulesAgree(text: String, expected: Bool) {
        #expect(conflict(text) == expected)
    }

    /// Cases that the old app rule accepted and the helper refused. The helper rule wins.
    @Test(arguments: [
        "# BEGIN JERD\n::1 shop.test\n# END JERD",
        "# BEGIN JERD\n127.0.0.1 shop.test\n",
        "# BEGIN JERD\n127.0.0.1 x.test shop.test\n# END JERD",
        "# BEGIN JERD\n127.0.0.1 shop.test # note\n# END JERD",
        "# END JERD\n# BEGIN JERD\n127.0.0.1 shop.test",
        "# BEGIN JERD\n127.0.0.1 SHOP.test\n# END JERD",
        "# BEGIN JERD\n127.0.0.1 shop.test\n# END JERD\n# BEGIN JERD\n# END JERD\n",
    ])
    func aSectionThatTheHelperRefusesIsNotJerdsOwn(text: String) {
        #expect(conflict(text))
    }

    @Test func aHostnameIsComparedWithoutCaseOutsideTheSection() {
        #expect(HostsConflictRule.hasConflict(hostname: "SHOP.test", in: Data("10.0.0.1 shop.TEST".utf8)))
    }

    @Test(arguments: [
        ("old-app-one-site", "shop.test", false),
        ("old-app-two-sites", "api.test", false),
        ("old-app-two-sites", "shop.test", false),
        ("old-app-two-sites", "new.test", false),
        ("old-app-crlf-user-file", "demo.test", false),
        ("old-app-user-line-after-section", "shop.test", false),
        ("old-app-user-line-after-section", "nas.lan", true),
        ("macos-default", "localhost", true),
    ])
    func oldHostsFilesKeepTheirOwnSitesFreeOfConflicts(name: String, hostname: String, expected: Bool) throws {
        let data = try HostsSectionLayoutTests.golden(name)
        #expect(HostsConflictRule.hasConflict(hostname: hostname, in: data) == expected)
    }
}
