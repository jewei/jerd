import ArgumentParser

/// `./dev runtimes`: prepares, verifies, and embeds the pinned runtime payloads.
struct RuntimesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runtimes",
        abstract: "Prepare, verify, and embed the pinned runtime payloads.",
        discussion: """
            Pins come from Runtimes/runtimes.json. Payloads go to .build/runtimes/payloads/<group>/<payload ID> \
            with payload-receipt.json. Verified downloads stay in .build/runtimes/downloads, one file per SHA-256.
            """,
        subcommands: [
            RuntimesPrepareCommand.self, RuntimesVerifyCommand.self, RuntimesStatusCommand.self,
            RuntimesEmbedCommand.self,
        ])
}
