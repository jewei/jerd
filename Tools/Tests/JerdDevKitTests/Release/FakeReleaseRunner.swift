import Foundation
import os

@testable import JerdDevKit

/// Answers each command of a release from rules and records every invocation. It never starts a
/// process, so nothing is signed, notarized, or published.
///
/// A rule matches the program name and the leading arguments. The last added rule that matches wins,
/// so a test adds general answers first and the case it checks last. A rule can also change files,
/// for example to act as `lipo -thin` or `gh release download`.
final class FakeReleaseRunner: ProcessRunning {
    struct Answer: Sendable {
        var status: Int32 = 0
        var standardOutput = ""
        var standardError = ""
    }

    private struct Rule {
        var program: String
        var prefix: [String]
        var answer: @Sendable (Invocation) throws -> Answer
    }

    private let rules = OSAllocatedUnfairLock(initialState: [Rule]())
    private let invocations = OSAllocatedUnfairLock(initialState: [Invocation]())

    /// Answers `program` (the last path component) with arguments that start with `prefix`.
    func on(
        _ program: String, _ prefix: [String] = [], status: Int32 = 0, output: String = "", error: String = "",
        effect: @escaping @Sendable (Invocation) throws -> Void = { _ in }
    ) {
        on(program, prefix) { invocation in
            try effect(invocation)
            return Answer(status: status, standardOutput: output, standardError: error)
        }
    }

    func on(_ program: String, _ prefix: [String] = [], answer: @escaping @Sendable (Invocation) throws -> Answer) {
        rules.withLock { $0.append(Rule(program: program, prefix: prefix, answer: answer)) }
    }

    func run(_ invocation: Invocation, output: OutputMode) async throws -> InvocationResult {
        invocations.withLock { $0.append(invocation) }
        let program = invocation.executable.lastPathComponent
        let rule = rules.withLock { rules in
            rules.last { $0.program == program && invocation.arguments.starts(with: $0.prefix) }
        }
        let answer = try rule?.answer(invocation) ?? Answer()
        return InvocationResult(
            commandLine: invocation.commandLine, status: answer.status, standardOutput: answer.standardOutput,
            standardError: answer.standardError)
    }

    var recorded: [Invocation] { invocations.withLock { $0 } }

    /// The argument lists of every call of `program`, in order.
    func calls(_ program: String) -> [[String]] {
        recorded.filter { $0.executable.lastPathComponent == program }.map(\.arguments)
    }

    /// The calls of `program` whose arguments start with `prefix`.
    func calls(_ program: String, _ prefix: [String]) -> [[String]] {
        calls(program).filter { $0.starts(with: prefix) }
    }
}
