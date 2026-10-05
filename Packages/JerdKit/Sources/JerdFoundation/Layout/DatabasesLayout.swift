import Foundation

/// Paths of the database registry folder `databases/`.
public struct DatabasesLayout: Hashable, Sendable {
    public let root: URL

    /// The service and runtime registry, encoded with `JSONFileFormat.settings`.
    public var servicesFile: URL { root.file("services.json") }
    public var previousServicesFile: URL { root.file("services.previous.json") }
    public var instancesDirectory: URL { root.folder("instances") }

    /// The folder of one instance.
    public func instance(_ id: UUID) -> DatabaseInstanceLayout {
        DatabaseInstanceLayout(id: id, root: instancesDirectory.folder(id.uuidString))
    }
}
