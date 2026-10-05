/// Renders UI pages with fixtures to PNG files.
enum SnapshotStep {
    static func run(_ context: DevContext, pages: [String]) async throws {
        let invocation = SnapshotPlan.invocation(
            repository: context.repository, toolchain: context.toolchain, pages: pages)
        let output: OutputMode =
            context.console.verbose ? .stream : .streamMatching { !SwiftPMOutput.isProgress($0) }
        let result = try await context.run(invocation, output: output)
        // EX_USAGE: the renderer refused its arguments, for example an unknown page name.
        if result.status == 64, result.exceededTimeLimit == nil {
            throw DevFailure.usage("The snapshot renderer refused the arguments. See its message above.")
        }
        guard result.succeeded else {
            FailureLog.report(result, name: "snapshots", showsTail: true, context: context)
            throw DevFailure.checkFailed("The snapshot renderer \(result.failureSummary).")
        }
        context.console.success("Snapshots are in this folder:")
        context.console.detail(context.repository.relativePath(of: context.repository.snapshots))
    }
}
