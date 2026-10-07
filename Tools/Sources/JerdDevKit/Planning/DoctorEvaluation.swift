/// Turns the output of version probes into `doctor` findings. A `nil` output means that the probe
/// could not run or failed, so the program is missing.
enum DoctorEvaluation {
    static func xcode(versionOutput: String?, expected: ToolVersion?) -> DoctorFinding {
        guard let output = versionOutput, let actual = ToolVersion.parse(after: "Xcode", in: output) else {
            return DoctorFinding(prerequisite: .xcode, level: .missing, message: Prerequisite.xcode.missingMessage)
        }
        return compare(.xcode, actual: actual, expected: expected, pinFile: ".xcode-version")
    }

    static func swift(versionOutput: String?) -> DoctorFinding {
        guard let output = versionOutput, let actual = ToolVersion.parse(after: "Swift version", in: output) else {
            return DoctorFinding(prerequisite: .swift, level: .missing, message: Prerequisite.swift.missingMessage)
        }
        guard actual.major >= 6 else {
            return DoctorFinding(
                prerequisite: .swift, level: .missing,
                message: "Swift \(actual) is too old. \(Prerequisite.swift.installHint)")
        }
        return DoctorFinding(prerequisite: .swift, level: .ok, message: "Swift \(actual)")
    }

    static func swiftFormat(path: String?) -> DoctorFinding {
        guard let path, !path.isEmpty else {
            return DoctorFinding(
                prerequisite: .swiftFormat, level: .missing, message: Prerequisite.swiftFormat.missingMessage)
        }
        return DoctorFinding(prerequisite: .swiftFormat, level: .ok, message: "swift-format at \(path)")
    }

    static func xcodeGen(versionOutput: String?, expected: ToolVersion?) -> DoctorFinding {
        guard let output = versionOutput, let actual = ToolVersion.parse(after: "Version:", in: output) else {
            return DoctorFinding(
                prerequisite: .xcodeGen, level: .missing, message: Prerequisite.xcodeGen.missingMessage)
        }
        return compare(.xcodeGen, actual: actual, expected: expected, pinFile: "Tools/xcodegen-version")
    }

    static func gitHubCLI(versionOutput: String?) -> DoctorFinding {
        guard let output = versionOutput, let actual = ToolVersion.parse(after: "gh version", in: output) else {
            return DoctorFinding(
                prerequisite: .gitHubCLI, level: .information, message: Prerequisite.gitHubCLI.missingMessage)
        }
        return DoctorFinding(prerequisite: .gitHubCLI, level: .ok, message: "GitHub CLI \(actual)")
    }

    /// `doctor` fails only when a required program is missing. A version difference is a warning.
    static func exitStatus(of findings: [DoctorFinding]) -> ExitStatus {
        findings.contains { $0.level == .missing } ? .missingPrerequisite : .success
    }

    private static func compare(
        _ prerequisite: Prerequisite,
        actual: ToolVersion,
        expected: ToolVersion?,
        pinFile: String
    ) -> DoctorFinding {
        let found = "\(prerequisite.name) \(actual)"
        guard let expected else {
            return DoctorFinding(
                prerequisite: prerequisite, level: .warning, message: "\(found). \(pinFile) has no valid version.")
        }
        guard actual == expected else {
            return DoctorFinding(
                prerequisite: prerequisite, level: .warning,
                message: "\(found), but the repository is tested with \(expected) (\(pinFile)).")
        }
        return DoctorFinding(prerequisite: prerequisite, level: .ok, message: found)
    }
}
