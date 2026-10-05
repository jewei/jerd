import ArgumentParser

/// `./dev test`: unit tests of JerdKit targets, opt-in integration tests, and the Tools tests.
struct TestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run unit tests, for example ./dev test JerdWeb.",
        discussion: """
            Inherited JERD_* variables never reach the tests, except the variables of the selected \
            integration groups:
              web       JERD_PHP_CLI, JERD_PHP_FPM, JERD_CADDY (required);
                        JERD_SECOND_PHP_CLI, JERD_SECOND_PHP_FPM, JERD_KEEP_TEST_FILES (optional)
              database  JERD_DATABASE_RUNTIMES (required); JERD_OCCUPIED_DATABASE_PORT (optional)
              mail      JERD_MAIL_RUNTIME (required)
              storage   JERD_STORAGE_RUNTIME (required)
            Each group also sets JERD_INTEGRATION=1 and its own switch, for example \
            JERD_DATABASE_INTEGRATION=1. Set each path to an absolute path of a trusted local runtime.
            """)

    @Argument(help: ArgumentHelp("JerdKit targets to test, for example JerdWeb. Default: all.", valueName: "target"))
    var targets: [String] = []

    @Option(help: ArgumentHelp("Integration groups to enable: web, database, mail, storage.", valueName: "groups"))
    var integration: String?

    @Option(
        help: ArgumentHelp("Run only the tests whose identifier matches this regular expression.", valueName: "pattern")
    )
    var filter: String?

    @Flag(help: "Run the tests of the Tools package.")
    var tools = false

    @OptionGroup var options: GlobalOptions

    /// Kit tests run unless `--tools` is the only selection.
    var runsKitTests: Bool { !tools || !targets.isEmpty || integration != nil }

    func validate() throws {
        if let integration {
            do {
                _ = try IntegrationGroup.parseList(integration)
            } catch let failure as DevFailure {
                throw ValidationError(failure.message)
            }
        }
    }

    func run() async throws {
        let context = try options.context()
        let testTargets = try TestPlan.testTargets(for: targets, available: TestStep.availableTestTargets(context))
        let groups = try integration.map(IntegrationGroup.parseList) ?? []
        var sequence = StepSequence(console: context.console)
        if runsKitTests {
            await sequence.run(Stage.kitTests.title) {
                try await TestStep.kit(context, testTargets: testTargets, filter: filter, groups: groups)
            }
        }
        if tools {
            await sequence.run(Stage.toolTests.title) { try await TestStep.tools(context, filter: filter) }
        }
        try sequence.finish()
    }
}
