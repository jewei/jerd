import ArgumentParser

/// `./dev release`: prepares, validates, and publishes a signed app update from this Mac.
struct ReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Prepare, validate, and publish a signed app update.",
        subcommands: [])
}
