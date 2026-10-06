import Foundation

/// Where a harness ran: the macOS and Xcode versions and the exact source commit.
struct SystemFacts: Codable, Equatable, Sendable {
    /// The value of a fact that could not be read.
    static let unknown = "unknown"

    var macOSVersion: String
    var xcodeVersion: String
    var commit: String
    /// True when the working tree had changes or untracked files, so the commit alone does not
    /// describe the tested code.
    var dirty: Bool

    /// Reads the facts with `sw_vers`, `xcodebuild -version`, and `git`. A fact that cannot be read is
    /// `unknown`: the record must still be written, especially for a failure.
    static func read(_ context: DevContext) async -> SystemFacts {
        let root = context.repository.root
        let system = await output(SystemProgram.swVers, ["-productVersion"], context)
        let xcode = await output(context.toolchain.xcodebuild, ["-version"], context)
        let commit = await output(context.toolchain.git, ["-C", root.path, "rev-parse", "HEAD"], context)
        let status = await output(
            context.toolchain.git, ["-C", root.path, "status", "--porcelain", "--untracked-files=all"], context)
        return SystemFacts(
            macOSVersion: system ?? unknown,
            xcodeVersion: xcode.map { $0.split(separator: "\n").joined(separator: " ") } ?? unknown,
            commit: commit ?? unknown,
            dirty: status.map { !$0.isEmpty } ?? true)
    }

    private static func output(_ executable: URL, _ arguments: [String], _ context: DevContext) async -> String? {
        let invocation = Invocation(executable: executable, arguments: arguments, timeout: TimeLimit.probe)
        do {
            let result = try await context.run(invocation, output: .capture)
            guard result.succeeded else { return nil }
            return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
