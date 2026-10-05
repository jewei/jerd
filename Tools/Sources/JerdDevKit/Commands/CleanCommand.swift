import ArgumentParser

/// `./dev clean`: removes build output.
struct CleanCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Remove build output. Add --all for packages and runtimes.",
        discussion: """
            Removes .build/xcode, .build/snapshots, Packages/JerdKit/.build, and Tools/.build. With --all, \
            also removes .build/SourcePackages and .build/runtimes. The next build downloads the packages \
            again, and the runtimes must be prepared again.
            """)

    @Flag(help: "Also remove resolved packages and prepared runtimes.")
    var all = false

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let context = try options.context()
        try await StepSequence.runSingle("Clean", console: context.console) {
            try CleanStep.run(context, all: all)
        }
    }
}
