import Darwin
import JerdProcess
import os

/// Answers `lsof` for one real child: no listener before the start, and exactly the expected
/// loopback ports for the PID that the ownership check names.
final class PIDLsof: Sendable {
    private let ports: Set<UInt16>
    private let owner = OSAllocatedUnfairLock<pid_t?>(initialState: nil)

    init(ports: Set<UInt16>) { self.ports = ports }

    func answer(_ arguments: [String]) -> CommandResult {
        if arguments.contains("-iUDP") { return CommandResult(status: 1, output: "") }
        if let index = arguments.firstIndex(of: "-p"), let pid = pid_t(arguments[index + 1]) {
            owner.withLock { $0 = pid }
            let lines = ports.sorted().map { "n127.0.0.1:\($0)" }.joined(separator: "\n")
            return CommandResult(status: 0, output: "p\(pid)\n\(lines)\n")
        }
        guard let pid = owner.withLock({ $0 }) else { return CommandResult(status: 1, output: "") }
        return CommandResult(status: 0, output: "p\(pid)\n")
    }
}
