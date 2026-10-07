/// Plans the snapshot renderer run. Pages are rendered with fixtures into `.build/snapshots`.
enum SnapshotPlan {
    static func invocation(
        repository: Repository, toolchain: Toolchain, pages: [String], listOnly: Bool = false
    ) -> Invocation {
        Invocation(
            executable: toolchain.xcrun,
            arguments: [
                "swift", "run", "--package-path", repository.kitPackage.path, "-c", "debug",
                "jerd-snapshots", "--output", repository.snapshots.path,
            ] + (listOnly ? ["--list"] : []) + pages,
            workingDirectory: repository.root,
            timeout: TimeLimit.snapshots)
    }
}
