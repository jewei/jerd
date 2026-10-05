import Darwin
import Foundation
import JerdProcess
import os

/// Answers `lsof` from the fake children: each server owns the port in its arguments or its
/// `redis.conf`, a `--skip-networking` server owns none, and occupied ports belong to PID 1.
final class EngineLsof: Sendable {
    private let processes: FakeProcessController
    private let foreign = OSAllocatedUnfairLock<Set<UInt16>>(initialState: [])

    init(processes: FakeProcessController) { self.processes = processes }

    func occupy(_ port: UInt16) { foreign.withLock { _ = $0.insert(port) } }

    func answer(_ arguments: [String]) async -> CommandResult {
        let children = await processes.runningChildren
        if let query = arguments.first(where: { $0.hasPrefix("-iTCP:") }), let port = UInt16(query.dropFirst(6)) {
            if foreign.withLock({ $0.contains(port) }) { return CommandResult(status: 0, output: "p1\n") }
            let owners = children.filter { Self.port(of: $0.request) == port }.map { "p\($0.pid)\n" }
            return owners.isEmpty
                ? CommandResult(status: 1, output: "") : CommandResult(status: 0, output: owners.joined())
        }
        if arguments.contains("-iUDP") { return CommandResult(status: 1, output: "") }
        guard let index = arguments.firstIndex(of: "-p"), let pid = pid_t(arguments[index + 1]),
            let child = children.first(where: { $0.pid == pid }), let port = Self.port(of: child.request)
        else { return CommandResult(status: 1, output: "") }
        return CommandResult(status: 0, output: "p\(pid)\nn127.0.0.1:\(port)\n")
    }

    /// The TCP port of a fake server request, or nil for a socket-only server.
    static func port(of request: ProcessRequest) -> UInt16? {
        let arguments = request.arguments
        if arguments.contains("--skip-networking") { return nil }
        if let value = arguments.first(where: { $0.hasPrefix("--port=") }) { return UInt16(value.dropFirst(7)) }
        if let index = arguments.firstIndex(of: "-p") { return UInt16(arguments[index + 1]) }
        guard let file = arguments.first, file.hasSuffix("redis.conf"),
            let text = try? String(contentsOfFile: file, encoding: .utf8),
            let line = text.split(separator: "\n").first(where: { $0.hasPrefix("port ") })
        else { return nil }
        return UInt16(line.dropFirst(5))
    }
}
