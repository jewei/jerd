/// The named stages of `lint` and `check`. CI runs `./dev check`, so `Stage.check` is the CI contract.
enum Stage: CaseIterable, Sendable {
    case formatCheck
    case projectCheck
    case repositoryPolicies
    case kitTests
    case toolTests
    case debugBuild

    static let lint: [Stage] = [.formatCheck, .projectCheck, .repositoryPolicies]
    static let check: [Stage] = lint + [.kitTests, .toolTests, .debugBuild]

    var title: String {
        switch self {
        case .formatCheck: "Format check"
        case .projectCheck: "Project generation check"
        case .repositoryPolicies: "Repository policies"
        case .kitTests: "JerdKit tests"
        case .toolTests: "Tools tests"
        case .debugBuild: "Debug build"
        }
    }

    func run(_ context: DevContext) async throws {
        switch self {
        case .formatCheck: try await FormatStep.check(context)
        case .projectCheck: try await GenerateStep.check(context)
        case .repositoryPolicies: try PolicyStep.run(context)
        case .kitTests: try await TestStep.kit(context, testTargets: [], filter: nil, groups: [])
        case .toolTests: try await TestStep.tools(context, filter: nil)
        case .debugBuild: try await BuildStep.run(context, options: BuildOptions(verbose: context.console.verbose))
        }
    }

    /// Runs the stages in order, keeps going after a failure, and throws when any stage failed.
    static func runAll(_ stages: [Stage], context: DevContext) async throws {
        var sequence = StepSequence(console: context.console)
        for stage in stages {
            await sequence.run(stage.title) { try await stage.run(context) }
        }
        try sequence.finish()
    }
}
