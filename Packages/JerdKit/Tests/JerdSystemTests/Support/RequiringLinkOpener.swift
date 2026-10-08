import Foundation

@testable import JerdSystem

/// Opens links to an anonymous listener in this process with a code-signing requirement on the
/// helper side, like `XPCHelperLinkOpener`. A listener that does not satisfy it gives the real XPC
/// error of a stale helper.
struct RequiringLinkOpener: HelperLinkOpening {
    let endpoint: NSXPCListenerEndpoint
    let requirement: String

    func open(exporting responder: ConsentResponder, onClose: @escaping @Sendable () -> Void) throws -> any HelperLink {
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: (any JerdHelperProtocol).self)
        connection.exportedInterface = NSXPCInterface(with: (any JerdTrustConsentProtocol).self)
        connection.exportedObject = responder
        connection.setCodeSigningRequirement(requirement)
        connection.invalidationHandler = onClose
        connection.interruptionHandler = onClose
        connection.resume()
        return XPCHelperLink(connection: connection)
    }
}
