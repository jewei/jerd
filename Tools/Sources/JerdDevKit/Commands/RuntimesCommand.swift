import ArgumentParser

/// `./dev runtimes`: prepares, verifies, and embeds the pinned runtime payloads.
struct RuntimesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runtimes",
        abstract: "Prepare, verify, and embed the pinned runtime payloads.",
        subcommands: [])
}
