import ArgumentParser

/// `./dev generate`: makes `Jerd.xcodeproj` from `project.yml`.
struct GenerateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate Jerd.xcodeproj from project.yml with XcodeGen.")

    @Flag(help: "Change nothing. Fail when the committed project differs from a fresh generation.")
    var check = false

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let context = try options.context()
        if check {
            try await Stage.runAll([.projectCheck], context: context)
        } else {
            try await StepSequence.runSingle("Generate project", console: context.console) {
                try await GenerateStep.generate(context)
            }
        }
    }
}
