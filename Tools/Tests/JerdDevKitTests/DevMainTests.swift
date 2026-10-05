import ArgumentParser
import Testing

@testable import JerdDevKit

@Suite("Argument parsing and exit status")
struct DevMainTests {
    private func exitStatus(_ arguments: [String]) -> ExitStatus? {
        if case .exit(let status, _) = DevMain.parse(arguments) { return status }
        return nil
    }

    @Test(
        "maps usage errors to exit status 2",
        arguments: [
            ["unknown"],
            ["build", "--sign", "Developer ID"],
            ["build", "--team", "TEAM"],
            ["test", "--integration", "cache"],
            ["format", "--fix"],
        ])
    func usageErrors(arguments: [String]) {
        #expect(exitStatus(arguments) == .usage)
    }

    @Test(
        "maps help requests to exit status 0", arguments: [["--help"], ["help"], ["help", "test"], ["build", "-h"]])
    func helpRequests(arguments: [String]) {
        #expect(exitStatus(arguments) == .success)
    }

    @Test("parses each command with its options")
    func parsesCommands() throws {
        guard case .command(let command) = DevMain.parse(["test", "JerdWeb", "--integration", "web", "--verbose"])
        else {
            Issue.record("The arguments must parse.")
            return
        }
        let test = try #require(command as? TestCommand)
        #expect(test.targets == ["JerdWeb"])
        #expect(test.integration == "web")
        #expect(test.options.verbose)
        #expect(test.runsKitTests)
    }

    @Test("--tools alone runs only the tools tests")
    func toolsAlone() throws {
        guard case .command(let command) = DevMain.parse(["test", "--tools"]) else {
            Issue.record("The arguments must parse.")
            return
        }
        #expect(try #require(command as? TestCommand).runsKitTests == false)
    }

    @Test("without a command, the root command prints the help")
    func rootCommand() {
        guard case .command(let command) = DevMain.parse([]) else {
            Issue.record("The empty argument list must parse.")
            return
        }
        #expect(command is DevCommand)
    }

    @Test("maps run errors to their exit status and message")
    func describesRunErrors() {
        #expect(DevMain.describe(DevFailure.missingPrerequisite("m")) == (.missingPrerequisite, "m"))
        #expect(DevMain.describe(ValidationError("v")) == (.usage, "v"))
        let failure = InvocationFailure.exited(commandLine: "/bin/x", status: 2, standardErrorTail: "")
        #expect(DevMain.describe(failure) == (.checkFailed, "/bin/x failed with exit status 2."))
    }

    @Test("the help lists every command in a purpose group")
    func helpListsGroups() {
        let help = DevCommand.helpMessage()
        for group in ["EVERYDAY", "CODE QUALITY", "SETUP AND MAINTENANCE"] {
            #expect(help.contains(group))
        }
        for command in ["check", "test", "build", "snapshots", "format", "lint", "generate", "doctor", "clean"] {
            #expect(help.contains("  \(command) "))
        }
    }
}
