import Foundation
import JerdSystem
import os

/// Accepts XPC connections to the helper and gives each one its own session.
///
/// Order per connection: the owner rule (logged when it refuses), the lifetime count (refused while
/// the helper exits, so the client retries and launchd starts the helper again), the code-signing
/// requirement on the connection itself (so an exec or re-sign race cannot change the peer for
/// later messages), the reverse consent interface, the session, both close handlers, then `resume`.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate, Sendable {
    private static let log = Logger(subsystem: HelperServiceIdentity.helperIdentifier, category: "connections")

    private let requirement: String
    private let service: HelperService
    private let lifetime: HelperLifetime

    init(requirement: String, service: HelperService, lifetime: HelperLifetime = HelperLifetime()) {
        self.requirement = requirement
        self.service = service
        self.lifetime = lifetime
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let owner = connection.effectiveUserIdentifier
        if case .reject(let reason) = ConnectionAcceptPolicy.decide(effectiveUserID: owner) {
            Self.log.error("Refused a helper connection: \(reason, privacy: .public)")
            return false
        }
        guard let ticket = lifetime.open() else {
            Self.log.notice("Refused a helper connection while the idle helper exits.")
            return false
        }
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: (any JerdTrustConsentProtocol).self)
        let session = HelperSession(owner: owner, service: service, consent: ConsentRequester.over(connection))
        connection.exportedInterface = NSXPCInterface(with: (any JerdHelperProtocol).self)
        connection.exportedObject = session
        connection.invalidationHandler = {
            session.invalidate()
            ticket.close()
        }
        connection.interruptionHandler = {
            session.invalidate()
            ticket.close()
        }
        connection.resume()
        return true
    }
}
