import Foundation

@testable import JerdSystem

/// An old helper on an anonymous listener: plain error texts and a reverse consent call on configure.
///
/// `@unchecked Sendable` (test only): XPC calls it on its own queues; the connection list is behind a lock.
final class LegacyHelper: NSObject, LegacyJerdHelperProtocol, NSXPCListenerDelegate, @unchecked Sendable {
    let listener = NSXPCListener.anonymous()
    let pair: LoopbackListenerPair
    let status: Data
    let consent: Data
    private let lock = NSLock()
    private var connections: [NSXPCConnection] = []

    init(pair: LoopbackListenerPair, status: Data, consent: Data) {
        self.pair = pair
        self.status = status
        self.consent = consent
        super.init()
        listener.delegate = self
        listener.resume()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: (any LegacyJerdHelperProtocol).self)
        connection.remoteObjectInterface = NSXPCInterface(with: (any LegacyJerdTrustConsentProtocol).self)
        connection.exportedObject = self
        connection.resume()
        lock.withLock { connections.append(connection) }
        return true
    }

    func status(reply: @escaping @Sendable (Data?, String?) -> Void) { reply(status, nil) }

    func configureSite(_ request: Data, reply: @escaping @Sendable (String?) -> Void) {
        guard let connection = lock.withLock({ connections.last }),
            let app = connection.remoteObjectProxyWithErrorHandler({ _ in reply("transport") })
                as? any LegacyJerdTrustConsentProtocol
        else { return reply("no consent") }
        app.changeTrust(consent) { status in
            reply(status == 0 ? nil : "Cannot set Jerd certificate trust: OSStatus \(status)")
        }
    }

    func acquireListeners(reply: @escaping @Sendable (FileHandle?, FileHandle?, String?) -> Void) {
        reply(pair.http, pair.https, nil)
    }

    func releaseListeners(reply: @escaping @Sendable () -> Void) { reply() }
    func removeSetup(reply: @escaping @Sendable (String?) -> Void) {
        reply("Stop Jerd's environment before removing system setup.")
    }
    func recoverSetup(_ approval: Data, reply: @escaping @Sendable (String?) -> Void) { reply(nil) }
}
