import ArgumentParser

/// `./dev check updates`: the isolated Sparkle installation test with temporary signed apps.
struct CheckUpdatesCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "updates",
        abstract: "Test Sparkle installation with temporary signed apps and a loopback feed.",
        discussion: """
            Compiles a test app with the resolved Sparkle (run ./dev build first), signs version 1 and \
            version 2 with the identity, and serves a feed signed with a temporary key on 127.0.0.1. \
            Cases: no-update, altered-feed, altered-archive, success, refused-quit. The test apps copy \
            the Sparkle keys of Jerd's Info.plist and never load Jerd settings or services. Writes \
            .build/evidence/<date>-updates.json.
            """)

    @Option(help: ArgumentHelp("An Apple code-signing identity in the Keychain.", valueName: "identity"))
    var identity: String

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let context = try options.context()
        try await StepSequence.runSingle("Sparkle installation check", console: context.console) {
            try await UpdateCheckStep.run(context, identity: identity, effects: .live)
        }
    }
}
