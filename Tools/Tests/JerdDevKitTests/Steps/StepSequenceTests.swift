import Testing

@testable import JerdDevKit

@Suite("Step sequence and stages")
struct StepSequenceTests {
    @Test("runs every step after a failure and reports the most severe status")
    func keepsGoingAfterFailure() async {
        let output = RecordingTextOutput()
        var sequence = StepSequence(console: Console(output: output, verbose: false))
        var ran: [String] = []
        await sequence.run("One") {
            ran.append("one")
            throw DevFailure.checkFailed("bad format")
        }
        await sequence.run("Two") {
            ran.append("two")
            throw DevFailure.missingPrerequisite("no XcodeGen")
        }
        await sequence.run("Three") { ran.append("three") }
        #expect(ran == ["one", "two", "three"])
        #expect(sequence.records.map(\.status) == [.checkFailed, .missingPrerequisite, .success])
        #expect(sequence.exitStatus == .missingPrerequisite)
        #expect(output.standardError == "    error: bad format\n    error: no XcodeGen\n")
    }

    @Test("prints a summary and throws one failure that names the failed steps")
    func summarizes() async {
        let output = RecordingTextOutput()
        var sequence = StepSequence(console: Console(output: output, verbose: false))
        await sequence.run("Lint") { throw InvocationFailure.timedOut(commandLine: "x", limit: .seconds(1)) }
        await sequence.run("Build") {}
        #expect(throws: DevFailure(status: .checkFailed, message: "1 of 2 steps failed: Lint.")) {
            try sequence.finish()
        }
        #expect(output.standardOutput.contains("==> Summary\n    failed   Lint "))
        #expect(output.standardOutput.contains("    ok       Build "))
    }

    @Test("a single step has no summary and a short failure message")
    func singleStep() async {
        let output = RecordingTextOutput()
        await #expect(throws: DevFailure(status: .checkFailed, message: "Build failed.")) {
            try await StepSequence.runSingle("Build", console: Console(output: output, verbose: false)) {
                throw DevFailure.checkFailed("compiler error")
            }
        }
        #expect(!output.standardOutput.contains("Summary"))
    }

    @Test("formats durations in tenths of a second")
    func formatsDurations() {
        #expect(StepSequence.seconds(.milliseconds(1_250)) == "1.2 s")
        #expect(StepSequence.seconds(.seconds(61)) == "61.0 s")
    }

    @Test("check runs lint, both test suites, and the Debug build, in this order")
    func checkIsTheCIContract() {
        #expect(Stage.lint == [.formatCheck, .projectCheck, .repositoryPolicies])
        #expect(Stage.check == [.formatCheck, .projectCheck, .repositoryPolicies, .kitTests, .toolTests, .debugBuild])
        #expect(Set(Stage.check) == Set(Stage.allCases))
    }
}
