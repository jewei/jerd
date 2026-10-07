import ArgumentParser

/// `./dev release`: prepares, validates, and publishes a signed app update from this Mac.
struct ReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Prepare, validate, and publish a signed app update.",
        discussion: """
            Flow: bump the version in a pull request, prepare a private candidate from the merged commit, \
            validate it, then publish it. Publication makes the release public and opens a pull request \
            with the signed feed; merge it and resume. The private keys stay in the Keychain.
            """,
        subcommands: [
            ReleaseBumpCommand.self, ReleasePrepareCommand.self, ReleaseValidateCommand.self,
            ReleasePublishCommand.self, ReleaseStatusCommand.self, ReleaseResumeCommand.self, ReleaseCleanCommand.self,
        ])
}
