import Darwin
import Foundation
import JerdProcess
import os

/// Answers `lsof` from the fake children: a running Mailpit owns the ports of its `--smtp` and
/// `--listen` arguments, and occupied ports belong to PID 1.
final class MailLsof: Sendable {
    private let processes: FakeProcessController
    private let foreign = OSAllocatedUnfairLock<Set<UInt16>>(initialState: [])
    private let udp = OSAllocatedUnfairLock(initialState: false)

    init(processes: FakeProcessController) { self.processes = processes }

    /// Simulates another program that listens on `port`.
    func occupy(_ port: UInt16) { foreign.withLock { _ = $0.insert(port) } }

    /// Simulates a service that opens a UDP socket.
    func openUDP() { udp.withLock { $0 = true } }

    func answer(_ arguments: [String]) async -> CommandResult {
        let children = await processes.runningChildren
        if let query = arguments.first(where: { $0.hasPrefix("-iTCP:") }), let port = UInt16(query.dropFirst(6)) {
            if foreign.withLock({ $0.contains(port) }) { return CommandResult(status: 0, output: "p1\n") }
            let owners = children.filter { Self.ports(of: $0.request).contains(port) }.map { "p\($0.pid)\n" }
            return owners.isEmpty
                ? CommandResult(status: 1, output: "") : CommandResult(status: 0, output: owners.joined())
        }
        if arguments.contains("-iUDP") {
            return udp.withLock { $0 }
                ? CommandResult(status: 0, output: "p1\nn*:5353\n") : CommandResult(status: 1, output: "")
        }
        guard let index = arguments.firstIndex(of: "-p"), let pid = pid_t(arguments[index + 1]),
            let child = children.first(where: { $0.pid == pid })
        else { return CommandResult(status: 1, output: "") }
        let lines = Self.ports(of: child.request).sorted().map { "n127.0.0.1:\($0)\n" }
        return CommandResult(status: 0, output: "p\(pid)\n" + lines.joined())
    }

    /// The TCP ports in the `--smtp` and `--listen` arguments of a fake Mailpit request.
    static func ports(of request: ProcessRequest) -> Set<UInt16> {
        var ports: Set<UInt16> = []
        for flag in ["--smtp", "--listen"] {
            guard let index = request.arguments.firstIndex(of: flag), index + 1 < request.arguments.count,
                let port = request.arguments[index + 1].split(separator: ":").last.flatMap({ UInt16($0) })
            else { continue }
            ports.insert(port)
        }
        return ports
    }
}
