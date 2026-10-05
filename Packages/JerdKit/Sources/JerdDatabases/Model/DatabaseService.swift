import Foundation

/// One registered database service. Saved in `services.json`. Its runtime never changes.
public struct DatabaseService: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// The instance folder name `instances/<UUID>/`.
    public let id: UUID
    public var name: String
    public let runtimeID: String
    public var port: UInt16

    public init(id: UUID = UUID(), name: String, runtimeID: String, port: UInt16) {
        self.id = id
        self.name = name
        self.runtimeID = runtimeID
        self.port = port
    }
}
