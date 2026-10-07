import Darwin
import Foundation
import JerdFoundation

extension LoopbackPortGuard {
    /// Verifies that `pid` listens exactly on `127.0.0.1:<port>` for each expected port and nowhere else.
    ///
    /// - Parameters:
    ///   - requireExclusive: also require that no other process listens on an expected port.
    ///   - allowUDP: allow UDP sockets (PHP-FPM); data services must have none.
    public func verifyOwnership(
        pid: pid_t, expected ports: Set<UInt16>, requireExclusive: Bool = true, allowUDP: Bool = false
    ) async throws {
        let tcp = try await inspect(["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-Fn"])
        let expected = Set(ports.map { "127.0.0.1:\($0)" })
        let listed = tcp.status == 0 || (ports.isEmpty && tcp.status == 1 && tcp.output.isEmpty)
        guard listed, let report = ListenerReport.parse(tcp.output), report.addresses == expected else {
            throw JerdError.processFailed("The service opened an unexpected network listener. Expected loopback only.")
        }
        if !allowUDP {
            let udp = try await inspect(["-nP", "-a", "-p", String(pid), "-iUDP", "-Fn"])
            guard udp.status == 1, udp.output.isEmpty else {
                throw JerdError.processFailed("The service opened an unexpected UDP socket.")
            }
        }
        guard requireExclusive else { return }
        for port in ports.sorted() where try await listeningProcessIDs(on: port) != [pid] {
            throw JerdError.processFailed("Another process also uses port \(port). Each service needs its own port.")
        }
    }

    /// The PIDs with a TCP listener on `port` (any address). `lsof` status 1 with no output means none.
    func listeningProcessIDs(on port: UInt16) async throws -> Set<pid_t> {
        let result = try await inspect(["-nP", "-a", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fp"])
        if result.status == 1, result.output.isEmpty { return [] }
        guard result.status == 0, let report = ListenerReport.parse(result.output), !report.processIDs.isEmpty else {
            throw JerdError.unavailable("Cannot inspect local port \(port). No process was stopped.")
        }
        return report.processIDs
    }

    private func inspect(_ arguments: [String]) async throws -> CommandResult {
        let request = ProcessRequest(
            executable: lsofExecutable, arguments: arguments, workingDirectory: FileManager.default.temporaryDirectory)
        return try await commandRunner.run(request, timeout: Self.inspectionTimeout)
    }
}
