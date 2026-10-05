import Testing

@testable import JerdSnapshotSupport

@Suite("Snapshot options")
struct SnapshotOptionsTests {
    @Test("No arguments render every entry to the default folder")
    func defaults() throws {
        let options = try SnapshotOptions.parse([])
        #expect(options == SnapshotOptions(output: ".build/snapshots"))
    }

    @Test("The exact arguments of ./dev snapshots PAGE select the page")
    func devSnapshotsArguments() throws {
        // SnapshotPlan in Tools builds this list for `./dev snapshots Sites`.
        let options = try SnapshotOptions.parse(["--output", "/work/jerd/.build/snapshots", "Sites"])
        #expect(options == SnapshotOptions(output: "/work/jerd/.build/snapshots", filters: ["Sites"]))
    }

    @Test("Positional names and filter names add up")
    func positionalAndFilterNames() throws {
        let options = try SnapshotOptions.parse(["sites", "--filter", "gallery", "mail", "--list", "dashboard"])
        #expect(options.filters == ["sites", "gallery", "mail", "dashboard"])
        #expect(options.listOnly)
    }

    @Test("Output, several filters, and list parse together")
    func parsesAllOptions() throws {
        let options = try SnapshotOptions.parse(["--filter", "gallery", "sites", "--output", "out", "--list"])
        #expect(options == SnapshotOptions(output: "out", filters: ["gallery", "sites"], listOnly: true))
    }

    @Test("The contrast pass option selects the Increase Contrast pass")
    func contrastPass() throws {
        let options = try SnapshotOptions.parse(["--contrast-pass", "--output", "out", "gallery-status"])
        #expect(options == SnapshotOptions(output: "out", filters: ["gallery-status"], contrast: .increased))
    }

    @Test("Cocoa defaults arguments and their values are not page names")
    func cocoaArguments() throws {
        let options = try SnapshotOptions.parse(["-AppleAccentColor", "0", "sites", "-AppleLanguages", "(fr)"])
        #expect(options.filters == ["sites"])
    }

    @Test("Help is accepted in its long and short form")
    func help() throws {
        #expect(try SnapshotOptions.parse(["--help"]).showHelp)
        #expect(try SnapshotOptions.parse(["-h"]).showHelp)
    }

    @Test(
        "An option without its value is refused",
        arguments: [["--output"], ["--filter"], ["--output", "--list"], ["-AppleAccentColor"]])
    func missingValue(arguments: [String]) {
        #expect(throws: SnapshotOptionsError.missingValue(arguments[0])) {
            try SnapshotOptions.parse(arguments)
        }
    }

    @Test("An unknown option is refused", arguments: ["--colour", "-x"])
    func unknownArgument(argument: String) {
        #expect(throws: SnapshotOptionsError.unknownArgument(argument)) {
            try SnapshotOptions.parse([argument])
        }
    }
}
