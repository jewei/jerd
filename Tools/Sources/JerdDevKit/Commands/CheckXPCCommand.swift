import ArgumentParser

/// `./dev check xpc`: the signed XPC check of the helper connection.
struct CheckXPCCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "xpc",
        abstract: "Check that signed XPC accepts only the Jerd code identities.")

    @Option(help: ArgumentHelp("An Apple code-signing identity in the Keychain.", valueName: "identity"))
    var identity: String

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        throw DevFailure.checkFailed("Not built yet.")
    }
}
