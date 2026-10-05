import JerdProcess

/// Where Caddy listens: inherited helper descriptors, or its own loopback ports (tests, preflight).
public struct ListenerBinding: Equatable, Hashable, Sendable {
    public let httpsPort: UInt16
    public let httpPort: UInt16
    /// True when Caddy receives bound listeners as descriptors 3 (HTTP) and 4 (HTTPS).
    public let inherited: Bool

    public init(httpsPort: UInt16, httpPort: UInt16, inherited: Bool) {
        self.httpsPort = httpsPort
        self.httpPort = httpPort
        self.inherited = inherited
    }

    /// The product binding: the helper's `127.0.0.1:443` and `127.0.0.1:80` descriptors.
    public static let product = ListenerBinding(httpsPort: 443, httpPort: 80, inherited: true)

    /// The fixed ports of a preflight `caddy validate`, which opens no listener.
    public static let preflight = ListenerBinding(httpsPort: 18_443, httpPort: 18_080, inherited: false)

    /// The Caddy `listen` value of the HTTPS server.
    var httpsAddress: String {
        inherited ? "fd/\(InheritedListeners.httpsDescriptor)" : "127.0.0.1:\(httpsPort)"
    }

    /// The Caddy `listen` value of the HTTP server.
    var httpAddress: String {
        inherited ? "fd/\(InheritedListeners.httpDescriptor)" : "127.0.0.1:\(httpPort)"
    }
}
