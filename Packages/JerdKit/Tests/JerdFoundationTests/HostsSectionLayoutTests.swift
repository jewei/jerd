import Foundation
import JerdFoundation
import Testing

/// The shared hosts section parser against hosts files in the exact form that the old app wrote.
@Suite struct HostsSectionLayoutTests {
    static func golden(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/Hosts/\(name)", withExtension: "hosts"))
        return try Data(contentsOf: url)
    }

    @Test(arguments: [
        ("old-app-one-site", ["shop.test"], "macos-default"),
        ("old-app-two-sites", ["api.test", "shop.test"], "macos-default"),
    ])
    func oldSectionsParseAndRemoveToTheOriginalBytes(name: String, names: [String], original: String) throws {
        let layout = try HostsSectionLayout.parse(try Self.golden(name))
        #expect(layout.section?.mappedNames == names)
        #expect(!layout.markersReversed)
        #expect(Data(layout.outside) == (try Self.golden(original)))
    }

    @Test func aCRLFUserFileKeepsItsBytesOutsideTheSection() throws {
        let layout = try HostsSectionLayout.parse(try Self.golden("old-app-crlf-user-file"))
        #expect(layout.section?.mappedNames == ["demo.test"])
        #expect(layout.outsideText == "127.0.0.1 localhost\r\n# café ✓\r\n")
    }

    @Test func aUserLineAfterTheSectionStaysOutsideIt() throws {
        let layout = try HostsSectionLayout.parse(try Self.golden("old-app-user-line-after-section"))
        #expect(layout.section?.mappedNames == ["shop.test"])
        #expect(Data(layout.outside) == (try Self.golden("macos-default")) + Data("10.0.0.5 nas.lan\n".utf8))
    }

    @Test func theDefaultHostsFileHasNoSection() throws {
        let layout = try HostsSectionLayout.parse(try Self.golden("macos-default"))
        #expect(layout.section == nil)
        #expect(Data(layout.outside) == (try Self.golden("macos-default")))
    }

    @Test func theMarkersAndTheAddressAreTheOldFormat() {
        #expect(HostsSectionLayout.beginMarker == "# BEGIN JERD")
        #expect(HostsSectionLayout.endMarker == "# END JERD")
        #expect(HostsSectionLayout.address == "127.0.0.1")
        #expect(HostsSectionLayout.maximumSize == 1_048_576)
    }
}
