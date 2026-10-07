import Foundation

/// The live link: a privileged Mach service connection to `dev.jerd.helper` that requires the
/// helper's code signature from the app's own team.
public struct XPCHelperLinkOpener: HelperLinkOpening {
    public init() {}

    public func open(
        exporting responder: ConsentResponder, onClose: @escaping @Sendable () -> Void
    ) throws
        -> any HelperLink
    {
        let requirement = try CodeSigningPolicy.requirement(
            identifier: HelperServiceIdentity.helperIdentifier, teamID: CodeSigningPolicy.currentTeamID())
        let connection = NSXPCConnection(machServiceName: HelperServiceIdentity.machServiceName, options: .privileged)
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
