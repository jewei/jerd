import ArgumentParser

/// `./dev lint`: the format check, the project check, and the repository policies.
struct LintCommand: DevSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Check format, project generation, and repository policies.",
        discussion: """
            Policies: the Sparkle keys in Info.plist, the Sparkle version pin, the app update feed URL and \
            public key, the appcast.xml structure and signature block, source files of 300 lines or fewer, \
            and relative links in Markdown documents.
            """)

    @OptionGroup var options: GlobalOptions

    func run() async throws {
        try await Stage.runAll(Stage.lint, context: options.context())
    }
}
