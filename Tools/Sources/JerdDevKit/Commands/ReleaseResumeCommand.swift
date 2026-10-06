import ArgumentParser

/// `./dev release resume`: continues a started publication from its recorded stage.
struct ReleaseResumeCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "Continue a started publication from the stage in state.json.",
        discussion: "Each step can run again safely. A finished publication reports that it is published.")

    @Argument(help: ArgumentHelp("The candidate folder in .build/releases.", valueName: "directory"))
    var directory: String

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        try await ReleasePublishCommand.publish(directory, options: options, resuming: true)
    }
}
