/// Renders UI pages with fixtures to PNG files.
enum SnapshotStep {
    static func run(_ context: DevContext, pages: [String]) async throws {
        let invocation = SnapshotPlan.invocation(
            repository: context.repository, toolchain: context.toolchain, pages: pages)
        let output: OutputMode =
            context.console.verbose ? .stream : .streamMatching { !SwiftPMOutput.isProgress($0) }
        let result = try await context.run(invocation, output: output)
        guard result.succeeded else {
            throw DevFailure.checkFailed("The snapshot renderer failed with exit status \(result.status).")
        }
        context.console.success("Snapshots are in this folder:")
        context.console.detail(context.repository.relativePath(of: context.repository.snapshots))
    }
}
