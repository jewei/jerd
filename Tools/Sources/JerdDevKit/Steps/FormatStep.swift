/// Formats Swift code, or checks its format, with the swift-format of the selected Xcode.
enum FormatStep {
    static func format(_ context: DevContext) async throws {
        try await requireSwiftFormat(context)
        let invocation = FormatPlan.format(repository: context.repository, toolchain: context.toolchain)
        try await context.runChecked(invocation, output: .stream)
        context.console.success("Formatted \(FormatPlan.formattedPaths.joined(separator: ", ")).")
    }

    static func check(_ context: DevContext) async throws {
        try await requireSwiftFormat(context)
        let invocation = FormatPlan.check(repository: context.repository, toolchain: context.toolchain)
        let result = try await context.run(invocation, output: .stream)
        guard result.succeeded else {
            throw DevFailure.checkFailed("swift-format found the problems above. Run ./dev format, then fix the rest.")
        }
        context.console.success("All Swift files have the configured format.")
    }

    private static func requireSwiftFormat(_ context: DevContext) async throws {
        let probe = Invocation(
            executable: context.toolchain.xcrun, arguments: ["--find", "swift-format"], timeout: TimeLimit.probe)
        let result = try? await context.run(probe, output: .capture)
        guard result?.succeeded == true else {
            throw DevFailure.missingPrerequisite(Prerequisite.swiftFormat.missingMessage)
        }
    }
}
