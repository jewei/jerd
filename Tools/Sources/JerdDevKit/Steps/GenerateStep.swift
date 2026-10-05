import Foundation

/// Generates `Jerd.xcodeproj` from `project.yml`, or checks that the committed project is current.
enum GenerateStep {
    static func generate(_ context: DevContext) async throws {
        let xcodegen = try context.toolchain.requireXcodeGen()
        let invocation = GeneratePlan.generate(root: context.repository.root, xcodegen: xcodegen)
        try await context.runChecked(invocation, output: .stream)
        context.console.success("Generated Jerd.xcodeproj from project.yml.")
    }

    /// Generates into a temporary copy of the repository and compares the result with the committed
    /// project. It never changes the working tree.
    static func check(_ context: DevContext) async throws {
        let xcodegen = try context.toolchain.requireXcodeGen()
        let repository = context.repository
        let listing = try await context.runChecked(
            GeneratePlan.listSourceFiles(repository: repository, toolchain: context.toolchain), output: .capture)
        let copyRoot = try FileTree.makeTemporaryFolder(prefix: "jerd-generate-check")
        defer { try? FileManager.default.removeItem(at: copyRoot) }
        try FileTree.copy(
            GeneratePlan.filesToCopy(fromGitOutput: listing.standardOutput), from: repository.root, to: copyRoot)
        try await context.runChecked(GeneratePlan.generate(root: copyRoot, xcodegen: xcodegen), output: .stream)
        let differences = ProjectComparison.differences(
            generated: try FileTree.readFiles(under: copyRoot.appending(path: "Jerd.xcodeproj")),
            committed: try FileTree.readFiles(under: repository.project))
        guard differences.isEmpty else {
            differences.forEach { context.console.error("Jerd.xcodeproj/\($0)") }
            throw DevFailure.checkFailed("Jerd.xcodeproj does not match project.yml. Run ./dev generate and commit it.")
        }
        context.console.success("Jerd.xcodeproj matches project.yml.")
    }
}
