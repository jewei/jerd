import ArgumentParser

/// `./dev format`: rewrites Swift files with the configured format.
struct FormatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "format",
        abstract: "Format all Swift code with swift-format.")

    @Flag(help: "Change nothing. Fail when a file does not have the configured format.")
    var check = false

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let context = try options.context()
        if check {
            try await Stage.runAll([.formatCheck], context: context)
        } else {
            try await StepSequence.runSingle("Format", console: context.console) {
                try await FormatStep.format(context)
            }
        }
    }
}
