import ArgumentParser

/// `./dev doctor`: checks the programs that the other commands need.
struct DoctorCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check the required programs and show install hints.")

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let context = try options.context()
        try await StepSequence.runSingle("Doctor", console: context.console) {
            try await DoctorStep.run(context)
        }
    }
}
