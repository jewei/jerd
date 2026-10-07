/// Renders UI pages with fixtures to PNG files.
enum SnapshotStep {
    static func run(_ context: DevContext, pages: [String], listOnly: Bool = false) async throws {
        let invocation = SnapshotPlan.invocation(
            repository: context.repository, toolchain: context.toolchain, pages: pages, listOnly: listOnly)
        let output: OutputMode =
            context.console.verbose ? .stream : .streamMatching { !SwiftPMOutput.isProgress($0) }
        let result = try await context.run(invocation, output: output)
        // The renderer exits with 2 when it refuses its arguments, for example an unknown page name.
        if result.status == ExitStatus.usage.rawValue, result.exceededTimeLimit == nil {
            throw DevFailure.usage("The snapshot renderer refused the arguments. See its message above.")
        }
        guard result.succeeded else {
            FailureLog.report(result, name: "snapshots", showsTail: true, context: context)
            throw DevFailure.checkFailed("The snapshot renderer \(result.failureSummary).")
        }
        if listOnly { return }
        context.console.success("Snapshots are in this folder:")
        context.console.detail(context.repository.relativePath(of: context.repository.snapshots))
    }
}
