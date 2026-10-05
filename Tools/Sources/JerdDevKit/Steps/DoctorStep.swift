import Foundation

/// Checks the programs that `./dev` needs and prints one line for each, with an install hint for a
/// missing program.
enum DoctorStep {
    static func run(_ context: DevContext) async throws {
        let findings = await findings(context)
        for finding in findings {
            switch finding.level {
            case .ok: context.console.success(finding.message)
            case .warning: context.console.warning(finding.message)
            case .missing: context.console.error(finding.message)
            case .information: context.console.detail("note: \(finding.message)")
            }
        }
        let status = DoctorEvaluation.exitStatus(of: findings)
        guard status == .success else {
            throw DevFailure(status: status, message: "Install the missing programs, then run ./dev doctor again.")
        }
    }

    static func findings(_ context: DevContext) async -> [DoctorFinding] {
        let toolchain = context.toolchain
        let xcode = await probe(context, toolchain.xcodebuild, ["-version"])
        let swift = await probe(context, toolchain.xcrun, ["swift", "--version"])
        let swiftFormat = await probe(context, toolchain.xcrun, ["--find", "swift-format"])
        let xcodeGen = await probe(context, toolchain.xcodegen, ["--version"])
        let gitHub = await probe(context, toolchain.gh, ["--version"])
        return [
            DoctorEvaluation.xcode(versionOutput: xcode, expected: pinnedVersion(context.repository.xcodeVersionFile)),
            DoctorEvaluation.swift(versionOutput: swift),
            DoctorEvaluation.swiftFormat(path: swiftFormat?.trimmingCharacters(in: .whitespacesAndNewlines)),
            DoctorEvaluation.xcodeGen(
                versionOutput: xcodeGen, expected: pinnedVersion(context.repository.xcodeGenVersionFile)),
            DoctorEvaluation.gitHubCLI(versionOutput: gitHub),
        ]
    }

    /// The combined output of a successful probe, or `nil` when the program is absent or fails.
    private static func probe(_ context: DevContext, _ executable: URL?, _ arguments: [String]) async -> String? {
        guard let executable else { return nil }
        let invocation = Invocation(executable: executable, arguments: arguments, timeout: TimeLimit.probe)
        guard let result = try? await context.run(invocation, output: .capture), result.succeeded else {
            return nil
        }
        return result.standardOutput + result.standardError
    }

    private static func pinnedVersion(_ file: URL) -> ToolVersion? {
        (try? String(contentsOf: file, encoding: .utf8)).flatMap(ToolVersion.init)
    }
}
