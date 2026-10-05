import Foundation
import JerdFoundation
import JerdProcess
import os

/// A command runner that answers from a table keyed by the argument list and records each call.
final class RecordingCommandRunner: CommandRunning {
    private let answers: [[String]: CommandResult]
    private let fallback: CommandResult
    private let calls = OSAllocatedUnfairLock<[[String]]>(initialState: [])

    init(_ answers: [[String]: CommandResult], fallback: CommandResult = CommandResult(status: 1, output: "")) {
        self.answers = answers
        self.fallback = fallback
    }

    var arguments: [[String]] { calls.withLock { $0 } }

    func run(_ request: ProcessRequest, timeout: Duration) async throws -> CommandResult {
        calls.withLock { $0.append(request.arguments) }
        return answers[request.arguments] ?? fallback
    }
}

/// The `lsof` argument lists that `LoopbackPortGuard` uses.
enum LsofQuery {
    static func listeners(on port: UInt16) -> [String] { ["-nP", "-a", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fp"] }
    static func tcp(of pid: pid_t) -> [String] { ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-Fn"] }
    static func udp(of pid: pid_t) -> [String] { ["-nP", "-a", "-p", String(pid), "-iUDP", "-Fn"] }
}
