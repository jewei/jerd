/// Builds the app with one `xcodebuild` call, checks the built app, and prints its path.
enum BuildStep {
    static func run(_ context: DevContext, options: BuildOptions) async throws {
        let invocation = BuildPlan.invocation(
            repository: context.repository, toolchain: context.toolchain, options: options)
        let output: OutputMode = options.verbose ? .stream : .streamMatching(BuildPlan.isDiagnostic)
        if options.allowsMissingRuntimes {
            context.console.warning(
                "Runtime payloads are not required. This app is for checks only; never ship it.")
        }
        let result = try await context.run(invocation, output: output)
        let configuration = options.configuration.rawValue
        guard result.succeeded else {
            let name = "\(configuration.lowercased())-build"
            FailureLog.report(result, name: name, showsTail: true, context: context)
            throw DevFailure.checkFailed("The \(configuration) build \(result.failureSummary).")
        }
        let app = BuildPlan.appURL(repository: context.repository, configuration: options.configuration)
        try await BuiltAppStep.check(context, app: app)
        let signing = options.signing.map { "signed with \($0.identity)" } ?? "unsigned"
        context.console.success("Built the \(signing) \(configuration) app:")
        context.console.detail(context.repository.relativePath(of: app))
    }
}
