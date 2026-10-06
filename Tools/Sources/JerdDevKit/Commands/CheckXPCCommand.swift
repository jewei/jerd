import ArgumentParser

/// `./dev check xpc`: the signed XPC check of the helper connection.
struct CheckXPCCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "xpc",
        abstract: "Check that signed XPC accepts only the Jerd code identities.",
        discussion: """
            Runs the JerdKit test SignedXPCCheckTests with JERD_XPC_IDENTITY set to the identity. The \
            test signs the JerdXPCCheck probe as the app and checks the socket transfer and both refusals. It \
            does not register a service or change system files. Writes .build/evidence/<date>-xpc.json.
            """)

    @Option(help: ArgumentHelp("An Apple code-signing identity in the Keychain.", valueName: "identity"))
    var identity: String

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        let context = try options.context()
        try await StepSequence.runSingle("Signed XPC check", console: context.console) {
            try await XPCCheckStep.run(context, identity: identity, clock: SystemHarnessClock())
        }
    }
}
