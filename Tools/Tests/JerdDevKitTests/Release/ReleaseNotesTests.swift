import Foundation
import Testing

@testable import JerdDevKit

@Suite("Release notes")
struct ReleaseNotesTests {
    static let changelog = """
        # Changelog

        ## [Unreleased]

        - New thing.
        - Other thing.

        ## [0.1.0] - 2026-09-01

        - First.

        """

    @Test("A bump moves the unreleased notes under the version heading")
    func promotes() throws {
        let promoted = try ReleaseNotes.promoted(Self.changelog, version: "0.2.0", date: "2026-10-06")
        #expect(promoted.contains("## [Unreleased]\n\n## [0.2.0] - 2026-10-06\n\n- New thing."))
        #expect(ReleaseNotes.unreleased(in: promoted) == "")
        #expect(try ReleaseNotes.section(for: "0.2.0", in: promoted) == "- New thing.\n- Other thing.\n")
    }

    @Test("A section ends at the next heading")
    func sectionEnds() throws {
        #expect(try ReleaseNotes.section(for: "0.1.0", in: Self.changelog) == "- First.\n")
    }

    @Test("Refuses empty notes, a missing section, and a version that has a section")
    func refuses() {
        let empty = "## [Unreleased]\n\n## [0.1.0] - 2026-09-01\n- First.\n"
        #expect(throws: DevFailure.self) { try ReleaseNotes.promoted(empty, version: "0.2.0", date: "2026-10-06") }
        #expect(throws: DevFailure.self) { try ReleaseNotes.promoted(Self.changelog, version: "0.1.0", date: "x") }
        #expect(throws: DevFailure.self) { try ReleaseNotes.section(for: "0.3.0", in: Self.changelog) }
        #expect(throws: DevFailure.self) { try ReleaseNotes.section(for: "0.2.0", in: "## [0.2.0] - 2026-10-06\n\n") }
    }

    @Test("Only a heading with a date names a release")
    func headingNeedsADate() {
        #expect(ReleaseNotes.isHeading("## [0.2.0] - 2026-10-06", of: "0.2.0"))
        #expect(!ReleaseNotes.isHeading("## [0.2.0] - soon", of: "0.2.0"))
        #expect(!ReleaseNotes.isHeading("## [0.2.0]", of: "0.2.0"))
    }

    @Test("The notes file states the system requirement")
    func notesFile() {
        let text = ReleaseNotes.file(notes: "- A.\n", minimumMacOS: ReleaseVersion("14.0")!)
        #expect(text == "- A.\n\nRequires Apple Silicon and macOS 14.0 or later.\n")
        #expect(ReleaseNotes.dateText(Date(timeIntervalSince1970: 0)) == "1970-01-01")
    }
}
