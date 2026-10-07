import Foundation

/// Asks a PHP-FPM socket for its ping response. The engine depends on this role so tests can use a fake.
public protocol FPMPinging: Sendable {
    /// Returns when FPM answered its ping correctly. Cancellation stops the wait.
    func ping(socket: URL) async throws
}
