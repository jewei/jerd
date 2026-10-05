import Testing

@testable import JerdDevKit

@Suite("Doctor evaluation and tool versions")
struct DoctorEvaluationTests {
    @Test("parses versions from real tool output")
    func parsesToolOutput() {
        #expect(ToolVersion.parse(after: "Xcode", in: "Xcode 27.0\nBuild version 27A266a") == ToolVersion("27.0"))
        #expect(
            ToolVersion.parse(after: "Swift version", in: "swift-driver version: 1.168.6 Apple Swift version 6.4 (x)")
                == ToolVersion("6.4"))
        #expect(ToolVersion.parse(after: "Version:", in: "Version: 2.46.0\n") == ToolVersion("2.46.0"))
        #expect(ToolVersion.parse(after: "gh version", in: "gh version 2.102.0 (2026-09-30)") == ToolVersion("2.102.0"))
        #expect(ToolVersion.parse(after: "Xcode", in: "xcode-select: error") == nil)
    }

    @Test("treats missing zero components as equal and compares numerically")
    func comparesVersions() throws {
        #expect(ToolVersion("27") == ToolVersion("27.0.0"))
        #expect(try #require(ToolVersion("2.9")) < #require(ToolVersion("2.10")))
        #expect(ToolVersion("27.0\n") == ToolVersion("27.0"))
        #expect(ToolVersion("27.x") == nil)
        #expect(ToolVersion("") == nil)
    }

    @Test("accepts the pinned Xcode and warns about another version")
    func comparesXcode() {
        let pinned = ToolVersion("27.0")
        #expect(DoctorEvaluation.xcode(versionOutput: "Xcode 27.0\n", expected: pinned).level == .ok)
        let other = DoctorEvaluation.xcode(versionOutput: "Xcode 26.6\n", expected: pinned)
        #expect(other.level == .warning)
        #expect(other.message == "Xcode 26.6, but the repository is tested with 27.0 (.xcode-version).")
    }

    @Test("reports a missing program with its install hint")
    func reportsMissingPrograms() {
        let xcode = DoctorEvaluation.xcode(versionOutput: nil, expected: nil)
        #expect(xcode.level == .missing)
        #expect(xcode.message.contains("sudo xcode-select --switch"))
        #expect(DoctorEvaluation.xcodeGen(versionOutput: nil, expected: nil).message.contains("brew install xcodegen"))
        #expect(DoctorEvaluation.swiftFormat(path: nil).level == .missing)
        #expect(DoctorEvaluation.swiftFormat(path: "").level == .missing)
    }

    @Test("refuses Swift before version 6")
    func refusesOldSwift() {
        #expect(DoctorEvaluation.swift(versionOutput: "Apple Swift version 5.10").level == .missing)
        #expect(DoctorEvaluation.swift(versionOutput: "Apple Swift version 6.0").level == .ok)
    }

    @Test("reports the GitHub CLI for information only")
    func gitHubCLIIsOptional() {
        let finding = DoctorEvaluation.gitHubCLI(versionOutput: nil)
        #expect(finding.level == .information)
        #expect(DoctorEvaluation.exitStatus(of: [finding]) == .success)
    }

    @Test("fails with the missing-prerequisite status only for a missing required program")
    func exitStatus() {
        let warning = DoctorFinding(prerequisite: .xcode, level: .warning, message: "")
        let missing = DoctorFinding(prerequisite: .xcodeGen, level: .missing, message: "")
        #expect(DoctorEvaluation.exitStatus(of: [warning]) == .success)
        #expect(DoctorEvaluation.exitStatus(of: [warning, missing]) == .missingPrerequisite)
    }

    @Test("only the GitHub CLI is optional")
    func requiredPrerequisites() {
        #expect(Prerequisite.allCases.filter { !$0.isRequired } == [.gitHubCLI])
    }
}
