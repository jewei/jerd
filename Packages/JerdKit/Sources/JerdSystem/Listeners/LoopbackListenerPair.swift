import Darwin
import Foundation
import JerdFoundation
import os

/// The HTTP and HTTPS listeners on IPv4 loopback that the helper binds and passes to the app.
///
/// Only descriptors cross the root boundary, never a network target or an executable. The app passes
/// them to Caddy as descriptors 3 and 4: `InheritedListeners(http: pair.http, https: pair.https)`.
public struct LoopbackListenerPair: Sendable {
    /// The standard ports that the helper binds.
    public static let standardPorts = (http: UInt16(80), https: UInt16(443))

    public let http: FileHandle
    public let https: FileHandle
    /// Shared by copies: a closed `FileHandle` raises an exception when its descriptor is read.
    private let closed = OSAllocatedUnfairLock(initialState: false)

    public init(http: FileHandle, https: FileHandle) {
        self.http = http
        self.https = https
    }

    /// Binds `127.0.0.1:<httpPort>` and `127.0.0.1:<httpsPort>`. Port 0 picks a free port.
    ///
    /// A fixed port that already has a listener is refused, also a wildcard one, which a bind with
    /// `SO_REUSEADDR` could otherwise shadow. When the second bind fails, the first
    /// listener is closed. See `listen(on:probe:)` for the one remaining window.
    public static func bind(httpPort: UInt16, httpsPort: UInt16) throws -> LoopbackListenerPair {
        try bind(httpPort: httpPort, httpsPort: httpsPort) { LoopbackSocket.accepts(port: $0) }
    }

    /// `bind(httpPort:httpsPort:)` with the probe that tells whether a listener accepts on a port.
    static func bind(
        httpPort: UInt16, httpsPort: UInt16, probe: (UInt16) -> Bool
    ) throws -> LoopbackListenerPair {
        guard httpPort != httpsPort || httpPort == 0 else {
            throw JerdError.invalid("HTTP and HTTPS need different sockets.")
        }
        let http = try listen(on: httpPort, probe: probe)
        do {
            return LoopbackListenerPair(http: http, https: try listen(on: httpsPort, probe: probe))
        } catch {
            try? http.close()
            throw error
        }
    }

    /// Binds one port without a check-then-bind race in the usual case.
    ///
    /// The first bind has no `SO_REUSEADDR`, so the kernel itself refuses it while any listener holds
    /// the port. Only when that bind finds the address in use does the probe run: a listener that
    /// accepts is refused, and otherwise lingering connections of an earlier listener hold the port,
    /// so the bind is repeated with `SO_REUSEADDR`. A wildcard listener that another process binds in
    /// the microseconds between that probe and that bind would be shadowed on loopback. This is
    /// harmless: the window needs lingering connections on the port, only Jerd's own server would get
    /// the loopback traffic, and once the root helper holds `127.0.0.1:<port>` the kernel refuses a
    /// wildcard bind of that port by another, non-root user.
    private static func listen(on port: UInt16, probe: (UInt16) -> Bool) throws -> FileHandle {
        if let handle = try LoopbackSocket.listen(on: port, reuseAddress: false) { return handle }
        if probe(port) {
            throw JerdError.unavailable(
                "Loopback port \(port) already has a listener. Stop the other service in its own app, then retry.")
        }
        if let handle = try LoopbackSocket.listen(on: port, reuseAddress: true) { return handle }
        throw LoopbackSocket.occupied(port, detail: SystemError.describe(EADDRINUSE))
    }

    /// The bound ports. Both handles must be listening IPv4 loopback TCP sockets.
    /// - Throws: `.invalid` after `close()`, or when a handle is not such a socket.
    public func ports() throws -> (http: UInt16, https: UInt16) {
        try closed.withLock { isClosed in
            guard !isClosed else { throw JerdError.invalid("The loopback listeners are closed.") }
            return (
                try LoopbackSocket.listeningPort(of: http.fileDescriptor),
                try LoopbackSocket.listeningPort(of: https.fileDescriptor)
            )
        }
    }

    /// Closes both listeners once. Later calls do nothing.
    public func close() {
        let first = closed.withLock { isClosed in
            defer { isClosed = true }
            return !isClosed
        }
        guard first else { return }
        try? http.close()
        try? https.close()
    }
}
