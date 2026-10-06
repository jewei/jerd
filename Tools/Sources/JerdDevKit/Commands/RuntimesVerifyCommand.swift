import ArgumentParser

/// `./dev runtimes verify [GROUP...]`: checks every prepared payload file by file.
struct RuntimesVerifyCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Verify every prepared payload against its pin and its receipt, file by file.")

    @Argument(help: ArgumentHelp("Groups to verify. Default: every group.", valueName: "group"))
    var groups: [String] = []

    @OptionGroup var options: GlobalOptions

    func validate() throws {
        do {
            _ = try RuntimeSelection.parse(groups)
        } catch let failure as DevFailure {
            throw ValidationError(failure.message)
        }
    }

    func run() async throws {
        let context = try options.context()
        let selection = try RuntimeSelection.parse(groups)
        try await StepSequence.runSingle("Verify runtime payloads", console: context.console) {
            try RuntimesVerifyStep.verify(context, groups: selection.groups)
        }
    }
}
