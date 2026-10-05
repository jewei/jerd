/// The document root that project detection suggests for a project folder.
public struct DocumentRootSuggestion: Equatable, Sendable {
    /// The canonical suggested document root.
    public let path: String
    /// True when the Laravel files exist. The suggestion is then `<project>/public`.
    public let isLaravel: Bool

    public init(path: String, isLaravel: Bool) {
        self.path = path
        self.isLaravel = isLaravel
    }

    /// A plain PHP project needs an explicit confirmation of its document root.
    public var requiresConfirmation: Bool { !isLaravel }
}
