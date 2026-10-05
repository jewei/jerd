import Darwin
import JerdProcess
import os

/// Answers the `lsof` queries of `LoopbackPortGuard` from a table: ports with a foreign listener,
/// and the service ports that the running fake child owns.
final class FakeLsof: Sendable {
    private struct Table {
        var foreign: Set<UInt16> = []
        var servicePorts: Set<UInt16> = []
        var portsByPID: [pid_t: Set<UInt16>] = [:]
        var extraListener: String?
    }

    private let table = OSAllocatedUnfairLock(initialState: Table())
    private let processes: FakeProcessController

    init(processes: FakeProcessController, servicePorts: Set<UInt16>) {
        self.processes = processes
        table.withLock { $0.servicePorts = servicePorts }
    }

    /// Simulates another program that listens on `port`.
    func occupy(_ port: UInt16) { table.withLock { _ = $0.foreign.insert(port) } }

    /// Simulates a service that opens one more listener, for example `*:3306`.
    func addListener(_ address: String) { table.withLock { $0.extraListener = address } }

    /// Makes `pid` own `ports` instead of the service ports, for example none in a setup phase.
    func setPorts(_ ports: Set<UInt16>, for pid: pid_t) { table.withLock { $0.portsByPID[pid] = ports } }

    func answer(_ arguments: [String]) async -> CommandResult {
        let table = table.withLock { $0 }
        if let query = arguments.first(where: { $0.hasPrefix("-iTCP:") }), let port = UInt16(query.dropFirst(6)) {
            if table.foreign.contains(port) { return CommandResult(status: 0, output: "p1\n") }
            if table.servicePorts.contains(port), let pid = await processes.runningPIDs.first {
                return CommandResult(status: 0, output: "p\(pid)\n")
            }
            return CommandResult(status: 1, output: "")
        }
        if arguments.contains("-iUDP") { return CommandResult(status: 1, output: "") }
        guard let index = arguments.firstIndex(of: "-p"), let pid = pid_t(arguments[index + 1]) else {
            return CommandResult(status: 1, output: "")
        }
        var lines = (table.portsByPID[pid] ?? table.servicePorts).sorted().map { "n127.0.0.1:\($0)" }
        if let extra = table.extraListener { lines.append("n\(extra)") }
        guard !lines.isEmpty else { return CommandResult(status: 1, output: "") }
        return CommandResult(status: 0, output: "p\(pid)\n" + lines.joined(separator: "\n") + "\n")
    }
}
