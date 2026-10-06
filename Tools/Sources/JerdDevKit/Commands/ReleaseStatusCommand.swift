import ArgumentParser
import Foundation

/// `./dev release status`: shows the stage of a candidate and the next action.
struct ReleaseStatusCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show the stage, history, and next action of a candidate.")

    @Argument(help: ArgumentHelp("The candidate folder in .build/releases.", valueName: "directory"))
    var directory: String

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let context = try options.context()
        let layout = try CandidateStore.existing(directory, workingDirectory: ReleaseValidateCommand.workingDirectory)
        try await StepSequence.runSingle("Release status", console: context.console) {
            let state = try CandidateStore.load(layout)
            let manifest = (try? Data(contentsOf: layout.manifest)).flatMap { try? ReleaseManifest.decode($0) }
            CandidateStatus.lines(state, manifest: manifest).forEach(context.console.detail)
        }
    }
}
