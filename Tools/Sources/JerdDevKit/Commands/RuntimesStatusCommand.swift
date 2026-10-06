import ArgumentParser

/// `./dev runtimes status`: one line for each pinned payload and for the XZ library.
struct RuntimesStatusCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "List the pinned payloads with their versions, sizes, and states.")

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let context = try options.context()
        try await StepSequence.runSingle("Runtime payloads", console: context.console) {
            try RuntimesVerifyStep.status(context)
        }
    }
}
