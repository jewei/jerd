import Foundation
import Testing

@testable import JerdDevKit

@Suite("Invocation values")
struct InvocationTests {
    @Test("shows plain words without quotes")
    func showsPlainWords() {
        let invocation = Invocation(
            executable: URL(filePath: "/usr/bin/xcrun"), arguments: ["swift", "test", "--filter", "^A\\."],
            timeout: .seconds(1))
        #expect(invocation.commandLine == "/usr/bin/xcrun swift test --filter '^A\\.'")
    }

    @Test(
        "quotes words that a shell would change",
        arguments: [
            ("a b", "'a b'"),
            ("", "''"),
            ("it's", "'it'\\''s'"),
            ("$(x)", "'$(x)'"),
            ("CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_ALLOWED=NO"),
        ])
    func quotesShellWords(word: String, shown: String) {
        #expect(Invocation.quotedForDisplay(word) == shown)
    }

    @Test("a successful result passes the check")
    func successfulResultPasses() throws {
        let result = InvocationResult(commandLine: "x", status: 0)
        #expect(try result.checked() == result)
    }

    @Test("a command log calls a successful command a success and a failed command a failure")
    func commandLogNamesTheOutcome() {
        let success = FailureLog.text(of: InvocationResult(commandLine: "/bin/true", status: 0))
        #expect(success.contains("Result: succeeded with exit status 0"))
        #expect(!success.contains("failed"))
        let failure = FailureLog.text(of: InvocationResult(commandLine: "/bin/false", status: 1))
        #expect(failure.contains("Result: failed with exit status 1"))
        let timeout = InvocationResult(commandLine: "/bin/sleep 9", status: 0, exceededTimeLimit: .seconds(5))
        #expect(FailureLog.text(of: timeout).contains("Result: stopped at the time limit of 5 s"))
    }

    @Test("a failed result throws with the command line, the status, and the end of standard error")
    func failedResultThrows() {
        let errors = (1...30).map { "line \($0)" }.joined(separator: "\n")
        let result = InvocationResult(commandLine: "/bin/x y", status: 4, standardError: errors)
        let tail = (11...30).map { "line \($0)" }.joined(separator: "\n")
        #expect(throws: InvocationFailure.exited(commandLine: "/bin/x y", status: 4, standardErrorTail: tail)) {
            try result.checked()
        }
    }

    @Test("a timed-out result keeps its output and throws the time-out")
    func timedOutResultThrows() {
        let result = InvocationResult(
            commandLine: "/bin/sleep 9", status: 143, standardOutput: "last words", exceededTimeLimit: .seconds(5))
        #expect(!result.succeeded)
        #expect(result.failureSummary == "stopped at the time limit of 5 s")
        #expect(throws: InvocationFailure.timedOut(commandLine: "/bin/sleep 9", limit: .seconds(5))) {
            try result.checked()
        }
    }

    @Test("failure messages name the command")
    func failureMessagesNameCommand() {
        #expect(
            InvocationFailure.timedOut(commandLine: "/bin/sleep 9", limit: .seconds(5)).description
                == "Stopped /bin/sleep 9 after the time limit of 5 s.")
        #expect(
            InvocationFailure.exited(commandLine: "/bin/false", status: 1, standardErrorTail: "").description
                == "/bin/false failed with exit status 1.")
    }
}
