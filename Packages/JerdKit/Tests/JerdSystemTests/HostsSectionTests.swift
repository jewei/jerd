import Foundation
import JerdFoundation
import Testing

@testable import JerdSystem

@Suite struct HostsSectionTests {
    private func hosts(_ names: String...) throws -> [Hostname] { try names.map { try Hostname($0) } }

    @Test func rendersTheExactSectionFormat() throws {
        #expect(
            HostsSection.render(try hosts("b.test", "a.test"))
                == "\n# BEGIN JERD\n127.0.0.1 a.test\n127.0.0.1 b.test\n# END JERD\n")
        #expect(HostsSection.render([]) == "")
    }

    @Test(arguments: [
        "127.0.0.1 localhost\n# user comment\n", "127.0.0.1 localhost", "127.0.0.1 localhost\r\n# café ✓\r\n", "",
    ])
    func addRenameAndRemoveReturnTheOriginalBytes(original: String) throws {
        let data = Data(original.utf8)
        let added = try HostsSection.replacing(in: data, with: hosts("demo.test"), expecting: [])
        let renamed = try HostsSection.replacing(
            in: added, with: hosts("other.test", "demo.test"), expecting: hosts("demo.test"))
        #expect(
            String(decoding: renamed, as: UTF8.self).hasSuffix(
                "127.0.0.1 demo.test\n127.0.0.1 other.test\n# END JERD\n"))
        let removed = try HostsSection.replacing(in: renamed, with: [], expecting: hosts("demo.test", "other.test"))
        #expect(removed == data)
    }

    @Test func multipleHostsPreserveUnrelatedMappings() throws {
        let original = Data("127.0.0.1 localhost\n10.0.0.1 nas.lan\n".utf8)
        let three = try HostsSection.replacing(in: original, with: hosts("a.test", "b.test", "c.test"), expecting: [])
        let one = try HostsSection.replacing(
            in: three, with: hosts("b.test"), expecting: hosts("c.test", "a.test", "b.test"))
        #expect(
            String(decoding: one, as: UTF8.self)
                == "127.0.0.1 localhost\n10.0.0.1 nas.lan\n\n# BEGIN JERD\n127.0.0.1 b.test\n# END JERD\n")
        #expect(throws: JerdError.invalid("The Jerd hosts section changed outside the app. It was not overwritten.")) {
            try HostsSection.replacing(in: one, with: [], expecting: hosts("a.test"))
        }
        #expect(try HostsSection.replacing(in: one, with: [], expecting: hosts("b.test")) == original)
    }

    @Test(arguments: [
        ("10.0.0.2 demo.test\n", "The hostname demo.test already has an external hosts mapping."),
        ("127.0.0.1 localhost DEMO.test # mine\n", "The hostname demo.test already has an external hosts mapping."),
        (
            "# BEGIN JERD\n127.0.0.1 x.test\n",
            "The Jerd hosts section has invalid markers. The hosts file was not changed."
        ),
        (
            "127.0.0.1 x.test\n# END JERD\n",
            "The Jerd hosts section has invalid markers. The hosts file was not changed."
        ),
        (
            "# BEGIN JERD\n127.0.0.1 x.test\n# END JERD\n",
            "An untracked Jerd hosts section already exists. It was not changed."
        ),
        ("# END JERD\n# BEGIN JERD\n", "An untracked Jerd hosts section already exists. It was not changed."),
        (
            "# BEGIN JERD\n# END JERD\n# BEGIN JERD\n# END JERD\n",
            "The Jerd hosts section has invalid markers. The hosts file was not changed."
        ),
    ])
    func refusesConflictingOrUntrackedHosts(contents: String, message: String) throws {
        #expect(throws: JerdError.invalid(message)) {
            try HostsSection.replacing(in: Data(contents.utf8), with: hosts("demo.test"), expecting: [])
        }
    }

    @Test func aMappingInsideTheReplacedSectionIsNotAConflict() throws {
        let data = Data("127.0.0.1 localhost\n\n# BEGIN JERD\n127.0.0.1 demo.test\n# END JERD\n".utf8)
        let result = try HostsSection.replacing(
            in: data, with: hosts("demo.test", "two.test"), expecting: hosts("demo.test"))
        #expect(HostsSection.maps(try hosts("demo.test", "two.test"), in: result))
    }

    @Test func refusesAMissingTrackedSection() throws {
        #expect(
            throws: JerdError.invalid("The tracked Jerd hosts section is missing. No external content was changed.")
        ) {
            try HostsSection.replacing(in: Data("127.0.0.1 localhost\n".utf8), with: [], expecting: hosts("demo.test"))
        }
    }

    /// Regression test: for a committed setup, a deleted section counts as removed; a changed one does not.
    @Test func aRecordedSectionThatIsGoneCountsAsRemoved() throws {
        let plain = Data("127.0.0.1 localhost\n".utf8)
        #expect(try HostsSection.replacing(in: plain, with: [], recorded: hosts("demo.test")) == plain)
        let added = try HostsSection.replacing(in: plain, with: hosts("demo.test"), recorded: hosts("demo.test"))
        #expect(added == plain + Data(HostsSection.render(try hosts("demo.test")).utf8))
        let changed = plain + Data(HostsSection.render(try hosts("other.test")).utf8)
        #expect(throws: JerdError.invalid("The Jerd hosts section changed outside the app. It was not overwritten.")) {
            try HostsSection.replacing(in: changed, with: [], recorded: hosts("demo.test"))
        }
    }

    @Test func refusesOversizedOrNonUTF8Files() throws {
        let message = "The hosts file is too large or is not valid UTF-8. It was not changed."
        #expect(throws: JerdError.invalid(message)) {
            try HostsSection.replacing(in: Data([0xFF, 0xFE, 0x0A]), with: [], expecting: [])
        }
        #expect(throws: JerdError.invalid(message)) {
            try HostsSection.replacing(in: Data(repeating: 0x20, count: 1_048_577), with: [], expecting: [])
        }
    }

    @Test func markersMustBeExactFullLines() throws {
        for line in [" # BEGIN JERD", "# BEGIN JERD ", "#BEGIN JERD", "# begin jerd"] {
            let data = Data("\(line)\n127.0.0.1 localhost\n".utf8)
            #expect(HostsSection.maps([], in: data))
        }
    }

    /// Regression test: a section that configure accepts is also reported as configured.
    @Test(arguments: [
        "# BEGIN JERD\n127.0.0.1 a.test\n127.0.0.1 b.test\n# END JERD\n127.0.0.1 localhost\n",
        "127.0.0.1 localhost\r\n# BEGIN JERD\r\n127.0.0.1 a.test\r\n127.0.0.1 b.test\r\n# END JERD\r\n",
        "127.0.0.1 localhost\n# BEGIN JERD\n127.0.0.1 a.test  \n\n127.0.0.1\tb.test\n# END JERD",
    ])
    func toleratedSectionVariantsAreReportedAndReplaceable(contents: String) throws {
        let data = Data(contents.utf8)
        #expect(HostsSection.maps(try hosts("a.test", "b.test"), in: data))
        #expect(!HostsSection.maps(try hosts("a.test"), in: data))
        let removed = try HostsSection.replacing(in: data, with: [], expecting: hosts("b.test", "a.test"))
        #expect(!String(decoding: removed, as: UTF8.self).contains("JERD"))
        #expect(String(decoding: removed, as: UTF8.self).contains("127.0.0.1 localhost"))
    }

    @Test(arguments: ["127.0.0.1 a.test b.test", "::1 a.test", "127.0.0.1 a.test # note"])
    func otherBodyLinesMeanTheSectionChanged(line: String) throws {
        let data = Data("# BEGIN JERD\n\(line)\n# END JERD\n".utf8)
        #expect(!HostsSection.maps(try hosts("a.test"), in: data))
    }

    @Test func mapsIsFalseWhenAnExternalLineAlsoMapsAJerdHost() throws {
        let data = Data("10.0.0.9 a.test\n\n# BEGIN JERD\n127.0.0.1 a.test\n# END JERD\n".utf8)
        #expect(!HostsSection.maps(try hosts("a.test"), in: data))
    }

    @Test func emptyHostListMeansNoSection() throws {
        #expect(HostsSection.maps([], in: Data("127.0.0.1 localhost\n".utf8)))
        #expect(!HostsSection.maps([], in: Data("\n# BEGIN JERD\n127.0.0.1 a.test\n# END JERD\n".utf8)))
    }
}
