/// Runs the JerdKit tests and the Tools tests with `swift test`.
enum TestStep {
    /// The JerdKit test targets, read from the folders in `Packages/JerdKit/Tests`.
    static func availableTestTargets(_ context: DevContext) throws -> [String] {
        try FileTree.subfolderNames(of: context.repository.kitTests).filter { $0.hasSuffix("Tests") }
    }

    /// - Parameter testTargets: Checked names from `TestPlan.testTargets`. Empty means all targets.
    static func kit(
        _ context: DevContext,
        testTargets: [String],
        filter: String?,
        groups: [IntegrationGroup]
    ) async throws {
        let environment = try TestEnvironment.make(inherited: context.environment, groups: groups)
        let invocation = TestPlan.kitTests(
            repository: context.repository, toolchain: context.toolchain,
            testTargets: testTargets, filter: filter, environment: environment)
        let result = try await context.run(invocation, output: outputMode(context))
        guard result.succeeded else {
            throw DevFailure.checkFailed("JerdKit tests failed with exit status \(result.status).")
        }
        let scope = testTargets.isEmpty ? "all JerdKit test targets" : testTargets.joined(separator: ", ")
        let integration =
            groups.isEmpty ? "" : " with integration groups \(groups.map(\.rawValue).joined(separator: ", "))"
        context.console.success("Tests passed for \(scope)\(integration).")
    }

    static func tools(_ context: DevContext, filter: String?) async throws {
        let environment = try TestEnvironment.make(inherited: context.environment, groups: [])
        let invocation = TestPlan.toolTests(
            repository: context.repository, toolchain: context.toolchain, filter: filter, environment: environment)
        let result = try await context.run(invocation, output: outputMode(context))
        guard result.succeeded else {
            throw DevFailure.checkFailed("Tools tests failed with exit status \(result.status).")
        }
        context.console.success("Tools tests passed.")
    }

    /// Every line in verbose mode; otherwise failures, diagnostics, and the final count.
    static func outputMode(_ context: DevContext) -> OutputMode {
        context.console.verbose ? .stream : .streamMatching(TestPlan.showsInQuietMode)
    }
}
