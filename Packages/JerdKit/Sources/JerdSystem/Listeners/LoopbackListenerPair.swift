import Darwin
import Foundation
import JerdFoundation

/// The HTTP and HTTPS listeners on IPv4 loopback that the helper binds and passes to the app.
///
/// Only descriptors cross the root boundary, never a network target or an executable. The app passes
/// them to Caddy as descriptors 3 and 4: `InheritedListeners(http: pair.http, https: pair.https)`.
public struct LoopbackListenerPair: Sendable {
    /// The standard ports that the helper binds.
    public static let standardPorts = (http: UInt16(80), https: UInt16(443))

    public let http: FileHandle
    public let https: FileHandle

    public init(http: FileHandle, https: FileHandle) {
        self.http = http
        self.https = https
    }

    /// Binds `127.0.0.1:<httpPort>` and `127.0.0.1:<httpsPort>`. Port 0 picks a free port.
    ///
    /// A fixed port that already accepts loopback connections (also through a wildcard listener,
    /// which a root bind with `SO_REUSEADDR` could otherwise shadow) is refused. When the second bind
    /// fails, the first listener is closed.
    public static func bind(httpPort: UInt16, httpsPort: UInt16) throws -> LoopbackListenerPair {
        guard httpPort != httpsPort || httpPort == 0 else {
            throw JerdError.invalid("HTTP and HTTPS need different sockets.")
        }
        for port in [httpPort, httpsPort] where port != 0 && LoopbackSocket.accepts(port: port) {
            throw JerdError.unavailable(
                "Loopback port \(port) already has a listener. Stop the other service in its own app, then retry.")
        }
        let http = try LoopbackSocket.listen(on: httpPort)
        do {
            return LoopbackListenerPair(http: http, https: try LoopbackSocket.listen(on: httpsPort))
        } catch {
            try? http.close()
            throw error
        }
    }

    /// The bound ports. Both handles must be listening IPv4 loopback TCP sockets.
    public func ports() throws -> (http: UInt16, https: UInt16) {
        (
            try LoopbackSocket.listeningPort(of: http.fileDescriptor),
            try LoopbackSocket.listeningPort(of: https.fileDescriptor)
        )
    }

    /// Closes both listeners. A handle that is already closed is ignored.
    public func close() {
        try? http.close()
        try? https.close()
    }
}
