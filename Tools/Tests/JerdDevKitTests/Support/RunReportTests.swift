import Testing

@testable import JerdDevKit

@Suite("JSON summary")
struct RunReportTests {
    @Test("keeps a stable schema: sorted keys, null message on success, and the step list")
    func encodesStableSchema() {
        let summary = RunReport.Summary(
            command: "lint", status: "failed", exitStatus: 1, message: "1 of 2 steps failed: Policies.",
            steps: [
                RunReport.Step(title: "Format check", status: "ok", seconds: 0.25, messages: []),
                RunReport.Step(
                    title: "Policies", status: "failed", seconds: 1.5,
                    messages: [RunReport.Message(level: "error", text: "appcast.xml: bad")]),
            ])
        #expect(
            RunReport.encoded(summary)
                == #"{"command":"lint","exitStatus":1,"message":"1 of 2 steps failed: Policies.","status":"failed","#
                + #""steps":[{"messages":[],"seconds":0.25,"status":"ok","title":"Format check"},"#
                + #"{"messages":[{"level":"error","text":"appcast.xml: bad"}],"seconds":1.5,"status":"failed","#
                + #""title":"Policies"}]}"#)
        let success = RunReport.Summary(command: "build", status: "ok", exitStatus: 0, message: nil, steps: [])
        #expect(
            RunReport.encoded(success)
                == #"{"command":"build","exitStatus":0,"message":null,"status":"ok","steps":[]}"#)
    }

    @Test("records each step with its status and its console messages")
    func recordsSteps() async {
        let report = RunReport()
        let output = RecordingTextOutput()
        await RunReport.$current.withValue(report) {
            var sequence = StepSequence(console: Console(output: output, verbose: false))
            await sequence.run("One") { Console(output: output, verbose: false).success("fine") }
            await sequence.run("Two") { throw DevFailure.missingPrerequisite("no XcodeGen") }
        }
        let summary = report.summary(command: "check", status: .missingPrerequisite, message: "m")
        #expect(summary.steps.map(\.title) == ["One", "Two"])
        #expect(summary.steps.map(\.status) == ["ok", "missing"])
        #expect(summary.steps[0].messages == [RunReport.Message(level: "ok", text: "fine")])
        #expect(summary.steps[1].messages == [RunReport.Message(level: "error", text: "no XcodeGen")])
        #expect(summary.exitStatus == 3)
    }
}
