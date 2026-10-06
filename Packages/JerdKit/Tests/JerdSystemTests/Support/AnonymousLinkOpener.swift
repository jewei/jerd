import Foundation

@testable import JerdSystem

/// Opens links to an anonymous listener in this process, without code-signing requirements.
struct AnonymousLinkOpener: HelperLinkOpening {
    let endpoint: NSXPCListenerEndpoint

    func open(exporting responder: ConsentResponder, onClose: @escaping @Sendable () -> Void) throws -> any HelperLink {
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: (any JerdHelperProtocol).self)
        connection.exportedInterface = NSXPCInterface(with: (any JerdTrustConsentProtocol).self)
        connection.exportedObject = responder
        connection.invalidationHandler = onClose
        connection.resume()
        return XPCHelperLink(connection: connection)
    }
}
