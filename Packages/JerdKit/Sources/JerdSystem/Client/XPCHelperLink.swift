import Foundation

/// An `NSXPCConnection` as a `HelperLink`.
///
/// `@unchecked Sendable` is safe here: the only stored property is immutable, and only the
/// `HelperConnection` actor calls `proxy` and `invalidate`, so the connection is never used from
/// two threads at once. The close handlers that XPC runs on its own queue do not touch it.
public final class XPCHelperLink: HelperLink, @unchecked Sendable {
    let connection: NSXPCConnection

    public init(connection: NSXPCConnection) { self.connection = connection }

    public func proxy(onError: @escaping @Sendable (any Error) -> Void) -> (any JerdHelperProtocol)? {
        connection.remoteObjectProxyWithErrorHandler(onError) as? any JerdHelperProtocol
    }

    public func invalidate() { connection.invalidate() }
}
