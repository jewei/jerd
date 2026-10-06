/// One open connection from the app to the helper. The live link is an `NSXPCConnection`;
/// tests use an in-memory link.
public protocol HelperLink: Sendable {
    /// A proxy whose transport failures go to `onError`. Nil when the interface is unavailable.
    func proxy(onError: @escaping @Sendable (any Error) -> Void) -> (any JerdHelperProtocol)?
    /// Closes the connection. Pending calls get a transport error.
    func invalidate()
}
