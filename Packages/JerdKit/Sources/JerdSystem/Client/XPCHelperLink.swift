import Foundation

/// An `NSXPCConnection` as a `HelperLink`.
///
/// `@unchecked Sendable` is safe here: the only stored property is immutable, and Apple documents
/// `NSXPCConnection` as safe to use from any thread (proxies, `invalidate`, and handlers).
public final class XPCHelperLink: HelperLink, @unchecked Sendable {
    let connection: NSXPCConnection

    public init(connection: NSXPCConnection) { self.connection = connection }

    public func proxy(onError: @escaping @Sendable (any Error) -> Void) -> (any JerdHelperProtocol)? {
        connection.remoteObjectProxyWithErrorHandler(onError) as? any JerdHelperProtocol
    }

    public func invalidate() { connection.invalidate() }
}
