/// Opens links to the helper.
public protocol HelperLinkOpening: Sendable {
    /// Opens a link that exports `responder` for reverse trust calls and calls `onClose` once the
    /// connection is invalidated or interrupted.
    func open(exporting responder: ConsentResponder, onClose: @escaping @Sendable () -> Void) throws -> any HelperLink
}
