/// Builds the app with one `xcodebuild` call and prints the path of the app.
enum BuildStep {
    static func run(_ context: DevContext, options: BuildOptions) async throws {
        let invocation = BuildPlan.invocation(
            repository: context.repository, toolchain: context.toolchain, options: options)
        let output: OutputMode = options.verbose ? .stream : .streamMatching(BuildPlan.isDiagnostic)
        let result = try await context.run(invocation, output: output)
        let configuration = options.configuration.rawValue
        guard result.succeeded else {
            let hint = options.verbose ? "" : " Run ./dev build --verbose for the full log."
            throw DevFailure.checkFailed("The \(configuration) build failed.\(hint)")
        }
        let app = BuildPlan.appURL(repository: context.repository, configuration: options.configuration)
        let signing = options.signing.map { "signed with \($0.identity)" } ?? "unsigned"
        context.console.success("Built the \(signing) \(configuration) app:")
        context.console.detail(context.repository.relativePath(of: app))
    }
}
