import ArgumentParser

/// `./dev check updates`: the isolated Sparkle installation test with temporary signed apps.
struct CheckUpdatesCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "updates",
        abstract: "Test Sparkle installation with temporary signed apps and a loopback feed.")

    @Option(help: ArgumentHelp("An Apple code-signing identity in the Keychain.", valueName: "identity"))
    var identity: String

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        throw DevFailure.checkFailed("Not built yet.")
    }
}
