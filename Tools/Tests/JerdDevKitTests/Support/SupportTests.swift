import Foundation
import Testing

@testable import JerdDevKit

@Suite("Repository, executable lookup, console, and exit status")
struct SupportTests {
    @Test("finds the repository root from a nested folder")
    func locatesRepository() {
        let markers: Set<String> = ["/work/jerd/project.yml", "/work/jerd/Tools/Package.swift"]
        let found = Repository.locate(from: URL(filePath: "/work/jerd/Packages/JerdKit/Sources")) {
            markers.contains($0)
        }
        #expect(found?.root.path == "/work/jerd")
    }

    @Test("finds no repository outside one")
    func locatesNothingOutside() {
        #expect(Repository.locate(from: URL(filePath: "/tmp/elsewhere")) { _ in false } == nil)
    }

    @Test("shows paths relative to the root, and other paths in full")
    func showsRelativePaths() {
        let repository = TestFixtures.repository
        #expect(repository.relativePath(of: repository.derivedData) == ".build/xcode")
        #expect(repository.relativePath(of: URL(filePath: "/work/jerdish/x")) == "/work/jerdish/x")
    }

    @Test("finds the first executable match in PATH and ignores relative entries")
    func findsExecutables() {
        let executables: Set<String> = ["/opt/homebrew/bin/xcodegen", "/usr/local/bin/xcodegen", "bin/gh"]
        let isExecutable: (String) -> Bool = { executables.contains($0) }
        let path = "bin:/usr/bin:/opt/homebrew/bin:/usr/local/bin"
        #expect(
            ExecutableLocator.find("xcodegen", searchPath: path, isExecutable: isExecutable)?.path
                == "/opt/homebrew/bin/xcodegen")
        #expect(ExecutableLocator.find("gh", searchPath: path, isExecutable: isExecutable) == nil)
        #expect(ExecutableLocator.find("xcodegen", searchPath: nil, isExecutable: isExecutable) == nil)
        #expect(ExecutableLocator.find("../xcodegen", searchPath: path, isExecutable: { _ in true }) == nil)
    }

    @Test("writes one style: step headers, indented details, and errors on standard error")
    func writesConsoleStyle() {
        let output = RecordingTextOutput()
        let console = Console(output: output, verbose: false)
        console.step("Lint")
        console.success("done")
        console.warning("old")
        console.detail("a\nb")
        console.error("broken")
        #expect(output.standardOutput == "==> Lint\n    ok: done\n    warning: old\n    a\n    b\n")
        #expect(output.standardError == "    error: broken\n")
    }

    @Test("shows command lines only in verbose mode")
    func showsCommandsWhenVerbose() {
        let invocation = Invocation(executable: URL(filePath: "/bin/echo"), arguments: ["a b"], timeout: .seconds(1))
        let quiet = RecordingTextOutput()
        Console(output: quiet, verbose: false).command(invocation)
        #expect(quiet.all.isEmpty)
        let verbose = RecordingTextOutput()
        Console(output: verbose, verbose: true).command(invocation)
        #expect(verbose.standardOutput == "    $ /bin/echo 'a b'\n")
    }

    @Test("keeps the stable exit codes")
    func keepsExitCodes() {
        #expect(ExitStatus.allCases.map(\.rawValue) == [0, 1, 2, 3])
    }

    @Test("a missing prerequisite outranks a failed check")
    func combinesStatuses() {
        #expect(ExitStatus.success.combined(with: .checkFailed) == .checkFailed)
        #expect(ExitStatus.checkFailed.combined(with: .missingPrerequisite) == .missingPrerequisite)
        #expect(ExitStatus.missingPrerequisite.combined(with: .checkFailed) == .missingPrerequisite)
        #expect(ExitStatus.success.combined(with: .success) == .success)
    }
}
