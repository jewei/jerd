import Foundation

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
        let downloads = context.repository.runtimeDownloads
        let environment = TestEnvironment.addingOnDemandDownloads(
            try TestEnvironment.make(inherited: context.environment, groups: groups) { group in
                try preparedPaths(context).variables(for: group)
            }, groups: groups,
            downloads: FileManager.default.fileExists(atPath: downloads.path) ? downloads.path : nil)
        let invocation = TestPlan.kitTests(
            repository: context.repository, toolchain: context.toolchain,
            testTargets: testTargets, filter: filter, environment: environment)
        let result = try await context.run(invocation, output: outputMode(context))
        guard result.succeeded else {
            FailureLog.report(result, name: "kit-tests", showsTail: result.exceededTimeLimit != nil, context: context)
            throw DevFailure.checkFailed("JerdKit tests \(result.failureSummary).")
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
            FailureLog.report(result, name: "tools-tests", showsTail: result.exceededTimeLimit != nil, context: context)
            throw DevFailure.checkFailed("Tools tests \(result.failureSummary).")
        }
        context.console.success("Tools tests passed.")
    }

    /// The runtime paths from the payloads that `./dev runtimes prepare` wrote.
    static func preparedPaths(_ context: DevContext) throws -> IntegrationRuntimePaths {
        let catalog = try PayloadInventory.catalog(at: context.repository.runtimeCatalog)
        return IntegrationRuntimePaths(
            inventory: PayloadInventory(root: context.repository.payloads, catalog: catalog),
            indexRoot: context.repository.integrationRuntimes)
    }

    /// Every line in verbose mode; otherwise failures with their details, diagnostics, and the final count.
    static func outputMode(_ context: DevContext) -> OutputMode {
        context.console.verbose ? .stream : .streamFiltered(QuietTestOutput())
    }
}
