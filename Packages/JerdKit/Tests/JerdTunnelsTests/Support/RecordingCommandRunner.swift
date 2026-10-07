import Foundation
import JerdProcess
import os

/// Answers each command from a script and records every request. It never starts a process.
final class RecordingCommandRunner: CommandRunning {
    typealias Script = @Sendable (_ executable: String, _ arguments: [String]) -> CommandResult

    private let script: OSAllocatedUnfairLock<Script>
    private let log = OSAllocatedUnfairLock<[[String]]>(initialState: [])

    init(_ script: @escaping Script = RecordingCommandRunner.healthy()) {
        self.script = OSAllocatedUnfairLock(initialState: script)
    }

    /// Every command line, with the executable path first.
    var commandLines: [[String]] { log.withLock { $0 } }

    func replaceScript(_ script: @escaping Script) { self.script.withLock { $0 = script } }

    func run(_ request: ProcessRequest, timeout: Duration) async throws -> CommandResult {
        let line = [request.executable.path] + request.arguments
        log.withLock { $0.append(line) }
        let script = script.withLock { $0 }
        return script(request.executable.path, request.arguments)
    }

    /// A Mac where every port is free: `lsof` lists no listener.
    static let freePorts: Script = { _, _ in CommandResult(status: 1, output: "") }

    /// A Mac where cloudflared reports `version`, the connector with `processID` listens only on its
    /// metrics port, and `/ready` answers `readyStatus`.
    static func healthy(
        version: String = "2026.9.3", processID: Int32 = 50_000, metricsPort: UInt16 = 20_241,
        readyStatus: String = "200"
    ) -> Script {
        { executable, arguments in
            switch (executable, arguments.first) {
            case (_, "--version"):
                return CommandResult(status: 0, output: "cloudflared version \(version) (built 2026-09-03)\n")
            case ("/usr/sbin/lsof", _) where arguments.contains("-p"):
                return CommandResult(status: 0, output: "p\(processID)\nf7\nn127.0.0.1:\(metricsPort)\n")
            case ("/usr/sbin/lsof", _) where arguments.contains("-iTCP:\(metricsPort)") && arguments.contains("-Fp"):
                return CommandResult(status: 0, output: "p\(processID)\n")
            case ("/usr/sbin/lsof", _):
                return CommandResult(status: 1, output: "")
            case ("/usr/bin/curl", _):
                return CommandResult(status: 0, output: readyStatus)
            default:
                return CommandResult(status: 127, output: "unexpected command")
            }
        }
    }
}
