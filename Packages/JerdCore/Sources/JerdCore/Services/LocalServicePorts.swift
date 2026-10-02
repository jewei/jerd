import Foundation

/// Checks both wildcard and exact-address listeners before a local service starts.
public struct LocalServicePorts: Sendable {
    private let commands: any CommandRunning
    private let directory: URL

    public init(directory: URL, commands: any CommandRunning = LocalCommandRunner()) {
        self.directory = directory
        self.commands = commands
    }

    public func requireAvailable(_ port: UInt16) async throws {
        guard port > 1023 else { throw JerdError.invalid("Use a port from 1024 to 65535.") }
        // SO_REUSEADDR alone permits a loopback bind beside a wildcard listener
        // on macOS. Inspect existing listeners before attempting the bind.
        guard try await listeningProcessIDs(on: port).isEmpty else {
            throw JerdError.unavailable("Local port \(port) is occupied. No process was stopped.")
        }
        try LoopbackPort.checkAvailable(port)
    }

    public func suggest(startingAt first: UInt16, excluding reserved: Set<UInt16> = []) async throws -> UInt16 {
        guard first > 1023 else { throw JerdError.invalid("Use an unprivileged service port.") }
        for value in Int(first)...min(Int(first) + 200, 65535) {
            let port = UInt16(value)
            if !reserved.contains(port), (try? await requireAvailable(port)) != nil { return port }
        }
        throw JerdError.unavailable("No free service port was found. Enter a different port.")
    }

    public func verify(processID: Int32, ports: Set<UInt16>) async throws {
        let result = try await commands.run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-a", "-p", String(processID), "-iTCP", "-sTCP:LISTEN", "-Fn"], directory: directory), timeout: .seconds(5))
        let actual = Set(result.output.split(separator: "\n").filter { $0.hasPrefix("n") }.map { String($0.dropFirst()) })
        let expected = Set(ports.map { "127.0.0.1:\($0)" })
        guard (result.status == 0 || (ports.isEmpty && result.status == 1)), actual == expected else {
            throw JerdError.process("The service opened an unexpected network listener. Expected loopback only.")
        }
        let udp = try await commands.run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-a", "-p", String(processID), "-iUDP", "-Fn"], directory: directory), timeout: .seconds(5))
        guard udp.status == 1, udp.output.isEmpty else { throw JerdError.process("The service opened an unexpected UDP socket.") }
        for port in ports {
            guard try await listeningProcessIDs(on: port) == [processID] else {
                throw JerdError.process("Another process also uses port \(port). Each service needs its own port.")
            }
        }
    }

    private func listeningProcessIDs(on port: UInt16) async throws -> Set<Int32> {
        let result = try await commands.run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-nP", "-a", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fp"], directory: directory), timeout: .seconds(5))
        if result.status == 1, result.output.isEmpty { return [] }
        let pids = Set(result.output.split(separator: "\n").filter { $0.hasPrefix("p") }.compactMap { Int32($0.dropFirst()) })
        guard result.status == 0, !pids.isEmpty else {
            throw JerdError.unavailable("Cannot inspect local port \(port). No process was stopped.")
        }
        return pids
    }
}
