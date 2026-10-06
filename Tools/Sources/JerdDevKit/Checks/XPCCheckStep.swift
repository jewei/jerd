/// Runs the signed XPC check and records its evidence.
enum XPCCheckStep {
    static let check = "xpc"

    static func run(_ context: DevContext, identity: String, clock: any HarnessClock) async throws {
        let harness = HarnessRun(check: check, identity: identity, context: context, clock: clock)
        try await harness.run { cases in
            let invocation = XPCCheckPlan.invocation(
                repository: context.repository, toolchain: context.toolchain, identity: identity,
                inherited: context.environment)
            let result = try await context.run(invocation, output: TestStep.outputMode(context))
            let evaluation = XPCCheckPlan.evaluate(result)
            cases = evaluation.cases
            if let failure = evaluation.failure {
                FailureLog.report(result, name: "check-xpc", showsTail: false, context: context)
                throw DevFailure.checkFailed(failure)
            }
        }
    }
}
