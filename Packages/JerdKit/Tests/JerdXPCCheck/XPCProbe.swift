import Foundation
import JerdFoundation
import JerdSystem

/// A probe helper on an anonymous listener that hands out two ephemeral loopback listeners.
///
/// `@unchecked Sendable` (check tool only): the stored properties are immutable after init, and the
/// result box is guarded by a lock.
final class XPCProbe: NSObject, JerdHelperProtocol, NSXPCListenerDelegate, @unchecked Sendable {
    let pair: LoopbackListenerPair
    private let requirement: String
    private let listener = NSXPCListener.anonymous()

    init(requirement: String) throws {
        self.requirement = requirement
        pair = try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
        super.init()
        listener.setConnectionCodeSigningRequirement(requirement)
        listener.delegate = self
        listener.resume()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: (any JerdHelperProtocol).self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    /// Connects with `clientRequirement` and asks for the listeners, waiting at most 10 seconds.
    func acquire(clientRequirement: String) -> Result<LoopbackListenerPair, any Error> {
        let client = NSXPCConnection(listenerEndpoint: listener.endpoint)
        client.remoteObjectInterface = NSXPCInterface(with: (any JerdHelperProtocol).self)
        client.setCodeSigningRequirement(clientRequirement)
        client.resume()
        defer { client.invalidate() }
        let box = ResultBox()
        let proxy = client.remoteObjectProxyWithErrorHandler { box.finish(.failure($0)) } as? any JerdHelperProtocol
        proxy?.acquireListeners { http, https, error in
            if let http, let https {
                box.finish(.success(LoopbackListenerPair(http: http, https: https)))
            } else {
                box.finish(.failure(JerdError.unavailable(error ?? "No sockets received")))
            }
        }
        guard box.done.wait(timeout: .now() + 10) == .success, let result = box.result else {
            return .failure(JerdError.unavailable("XPC did not return a result"))
        }
        return result
    }

    func status(reply: @escaping @Sendable (Data?, String?) -> Void) { reply(nil, "Not used by this check") }
    func configureSite(_ request: Data, reply: @escaping @Sendable (String?) -> Void) {
        reply("Not used by this check")
    }
    func acquireListeners(reply: @escaping @Sendable (FileHandle?, FileHandle?, String?) -> Void) {
        reply(pair.http, pair.https, nil)
    }
    func releaseListeners(reply: @escaping @Sendable () -> Void) { reply() }
    func removeSetup(reply: @escaping @Sendable (String?) -> Void) { reply("Not used by this check") }
    func recoverSetup(_ approval: Data, reply: @escaping @Sendable (String?) -> Void) {
        reply("Not used by this check")
    }
}
