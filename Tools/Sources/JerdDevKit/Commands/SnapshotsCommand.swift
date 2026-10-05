import ArgumentParser

/// `./dev snapshots`: renders UI pages with fixtures to PNG files.
struct SnapshotsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshots",
        abstract: "Render UI pages to PNG files in .build/snapshots.")

    @Argument(help: ArgumentHelp("Pages to render. Default: all pages.", valueName: "page"))
    var pages: [String] = []

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let context = try options.context()
        try await StepSequence.runSingle("Snapshots", console: context.console) {
            try await SnapshotStep.run(context, pages: pages)
        }
    }
}
