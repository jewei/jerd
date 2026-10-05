import Foundation
import JerdServiceKit

/// An installed database runtime folder. Saved in `services.json`; equality includes the path.
public struct DatabaseRuntime: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let engine: DatabaseEngine
    public let version: String
    /// The absolute runtime folder that contains `bin/`.
    public let path: String

    public init(id: String, engine: DatabaseEngine, version: String, path: String) {
        self.id = id
        self.engine = engine
        self.version = version
        self.path = path
    }

    /// The executable `<path>/bin/<name>`.
    public func executable(_ name: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("bin").appendingPathComponent(name)
    }

    /// True when the ID and version are safe identifiers and the path is absolute without
    /// control characters.
    public var isValid: Bool {
        SafeIdentifier.isValid(id) && SafeIdentifier.isValid(version) && SafeIdentifier.isAbsolutePath(path)
    }
}
