import ArgumentParser
import Foundation

/// `./dev release validate`: checks a prepared candidate again.
struct ReleaseValidateCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Check the signatures, notarization, payloads, symbols, feed, and disk image of a candidate.",
        discussion: """
            The feed and disk image signatures are checked with the committed public key. Without \
            --public-key-only, the command also checks that the Keychain key belongs to that public key.
            """)

    @Argument(help: ArgumentHelp("The candidate folder in .build/releases.", valueName: "directory"))
    var directory: String

    @Flag(help: "Do not use the Keychain. Any Mac can run this check.")
    var publicKeyOnly = false

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let environment = try ReleaseEnvironment.live(try options.context())
        let layout = try CandidateStore.existing(directory, workingDirectory: Self.workingDirectory)
        try await StepSequence.runSingle("Release validation", console: environment.console) {
            try await ReleaseValidator(shell: environment.shell, layout: layout, verifier: environment.verifier).run(
                publicKeyOnly: publicKeyOnly)
        }
    }

    /// `./dev` runs from the repository root, so a relative folder is relative to it.
    static var workingDirectory: URL { URL(filePath: FileManager.default.currentDirectoryPath) }
}
