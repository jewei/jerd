import Darwin
import Foundation
import JerdFoundation

/// Checks that a loopback service port is free before a start, and that the started service
/// owns exactly its expected loopback listeners afterwards.
///
/// On macOS, `SO_REUSEADDR` lets a loopback bind succeed beside a wildcard listener, so a bind
/// check alone is not enough: any existing TCP listener on the port (from `lsof`, or one that
/// accepts a loopback connection) makes the port occupied.
public struct LoopbackPortGuard: Sendable {
    /// The lowest port that a service may use.
    public static let minimumPort: UInt16 = 1_024
    /// How many ports after the first `suggest` tries.
    public static let suggestionSpan = 200
    /// The timeout of each `lsof` call.
    public static let inspectionTimeout: Duration = .seconds(5)

    let commandRunner: any CommandRunning
    let probe: LoopbackProbe
    let lsofExecutable: URL

    public init(
        commands: any CommandRunning = CommandRunner(), probe: LoopbackProbe = .system,
        lsof: URL = URL(fileURLWithPath: "/usr/sbin/lsof")
    ) {
        commandRunner = commands
        self.probe = probe
        lsofExecutable = lsof
    }

    /// Requires a service port (1024 or above) that is free on every address: no listener that
    /// `lsof` reports, no listener that accepts a loopback connection (for example one of another
    /// user, which `lsof` cannot see), and a successful loopback bind.
    public func requireFree(_ port: UInt16) async throws {
        guard port >= Self.minimumPort else { throw JerdError.invalid("Use a port from 1024 to 65535.") }
        try await requireNoListener(port)
        guard !probe.isAccepting(port) else { throw occupied(port) }
        try probe.requireBindable(port)
    }

    /// Requires that `lsof` reports no TCP listener on `port` on any address. Any port, including
    /// 80 and 443. It makes no connection, so it does not see listeners of other users.
    public func requireNoListener(_ port: UInt16) async throws {
        guard try await listeningProcessIDs(on: port).isEmpty else { throw occupied(port) }
    }

    /// The first free port from `first` to `first + 200` that is not in `excluding`.
    public func suggest(startingAt first: UInt16, excluding reserved: Set<UInt16> = []) async throws -> UInt16 {
        guard first >= Self.minimumPort else { throw JerdError.invalid("Use an unprivileged service port.") }
        for value in Int(first)...min(Int(first) + Self.suggestionSpan, Int(UInt16.max)) {
            let port = UInt16(value)
            guard !reserved.contains(port) else { continue }
            do {
                try await requireFree(port)
                return port
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue  // Occupied or not inspectable: try the next port.
            }
        }
        throw JerdError.unavailable("No free service port was found. Enter a different port.")
    }

    private func occupied(_ port: UInt16) -> JerdError {
        .unavailable("Local port \(port) is occupied. No process was stopped.")
    }
}
