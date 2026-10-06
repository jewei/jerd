import Foundation

/// A weak reference to a connection.
///
/// `@unchecked Sendable` is safe: the weak property is written once at init, and weak loads are
/// atomic in Swift; `NSXPCConnection` is documented as safe to use from any thread.
final class WeakConnection: @unchecked Sendable {
    weak var connection: NSXPCConnection?

    init(_ connection: NSXPCConnection) { self.connection = connection }
}
