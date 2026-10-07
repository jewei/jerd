import Darwin
import JerdFoundation

/// Direct socket checks of one IPv4 loopback port, used beside `lsof`.
public struct LoopbackProbe: Sendable {
    /// True when a connection to `127.0.0.1:<port>` is accepted, also by a listener that `lsof`
    /// cannot see (for example a root-owned wildcard listener).
    public var isAccepting: @Sendable (UInt16) -> Bool
    /// Binds and listens on `127.0.0.1:<port>` with `SO_REUSEADDR` (never `SO_REUSEPORT`), then closes.
    public var requireBindable: @Sendable (UInt16) throws -> Void

    public init(
        isAccepting: @escaping @Sendable (UInt16) -> Bool, requireBindable: @escaping @Sendable (UInt16) throws -> Void
    ) {
        self.isAccepting = isAccepting
        self.requireBindable = requireBindable
    }

    /// The real socket checks.
    public static let system = LoopbackProbe(
        isAccepting: { LoopbackSocket.accepts(port: $0, timeout: .milliseconds(250)) },
        requireBindable: LoopbackSocket.requireBindable)
}
