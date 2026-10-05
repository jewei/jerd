import Foundation
import JerdSystem
import os

/// Accepts XPC connections to the helper and gives each one its own session.
///
/// Order per connection: the owner rule (logged when it refuses), the code-signing requirement on
/// the connection itself (so an exec or re-sign race cannot change the peer for later messages),
/// the reverse consent interface, the session, both close handlers, then `resume`.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate, Sendable {
    private static let log = Logger(subsystem: HelperServiceIdentity.helperIdentifier, category: "connections")

    private let requirement: String
    private let service: HelperService

    init(requirement: String, service: HelperService) {
        self.requirement = requirement
        self.service = service
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        let owner = connection.effectiveUserIdentifier
        if case .reject(let reason) = ConnectionAcceptPolicy.decide(effectiveUserID: owner) {
            Self.log.error("Refused a helper connection: \(reason, privacy: .public)")
            return false
        }
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: (any JerdTrustConsentProtocol).self)
        let session = HelperSession(owner: owner, service: service, consent: ConsentRequester.over(connection))
        connection.exportedInterface = NSXPCInterface(with: (any JerdHelperProtocol).self)
        connection.exportedObject = session
        connection.invalidationHandler = { session.invalidate() }
        connection.interruptionHandler = { session.invalidate() }
        connection.resume()
        return true
    }
}
