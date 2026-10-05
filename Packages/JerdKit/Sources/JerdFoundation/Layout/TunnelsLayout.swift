import Foundation

/// Paths of the tunnel registry folder `tunnels/`.
public struct TunnelsLayout: Hashable, Sendable {
    public let root: URL

    public var settingsFile: URL { root.file(ServiceFileName.settings) }
    public var previousSettingsFile: URL { root.file(ServiceFileName.previousSettings) }
    public var instancesDirectory: URL { root.folder("instances") }

    /// The folder of one connector.
    public func instance(_ id: UUID) -> TunnelInstanceLayout {
        TunnelInstanceLayout(id: id, root: instancesDirectory.folder(id.uuidString))
    }
}
