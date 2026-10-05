import Testing

@testable import JerdDesign

@Suite("Snapshot options")
struct SnapshotOptionsTests {
    @Test("No arguments render every entry to the default folder")
    func defaults() throws {
        let options = try SnapshotOptions.parse([])
        #expect(options == SnapshotOptions(output: ".build/snapshots"))
    }

    @Test("Output, several filters, and list parse together")
    func parsesAllOptions() throws {
        let options = try SnapshotOptions.parse(["--filter", "gallery", "sites", "--output", "out", "--list"])
        #expect(options == SnapshotOptions(output: "out", filters: ["gallery", "sites"], listOnly: true))
    }

    @Test("Repeated filter options add their names")
    func repeatedFilters() throws {
        let options = try SnapshotOptions.parse(["--filter", "a", "--filter", "b"])
        #expect(options.filters == ["a", "b"])
    }

    @Test("Help is accepted in its long and short form")
    func help() throws {
        #expect(try SnapshotOptions.parse(["--help"]).showHelp)
        #expect(try SnapshotOptions.parse(["-h"]).showHelp)
    }

    @Test("An option without its value is refused", arguments: [["--output"], ["--filter"], ["--output", "--list"]])
    func missingValue(arguments: [String]) {
        #expect(throws: SnapshotOptionsError.missingValue(arguments[0])) {
            try SnapshotOptions.parse(arguments)
        }
    }

    @Test("An unknown argument is refused")
    func unknownArgument() {
        #expect(throws: SnapshotOptionsError.unknownArgument("--colour")) {
            try SnapshotOptions.parse(["--colour"])
        }
    }
}
