import Foundation
import JerdServiceKit

/// An installed RustFS runtime folder. Saved in `storage/settings.json`, as the data identity
/// (`storage/runtime.json`), and in `initialized.json`. Equality includes the path.
public struct StorageRuntime: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let version: String
    /// The absolute runtime folder that contains `rustfs`.
    public let path: String

    public init(id: String, version: String, path: String) {
        self.id = id
        self.version = version
        self.path = path
    }

    /// The executable `<path>/rustfs`.
    public var executable: URL {
        URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("rustfs")
    }

    /// True when the ID and version are safe identifiers and the path is absolute without
    /// control characters.
    public var isValid: Bool {
        SafeIdentifier.isValid(id) && SafeIdentifier.isValid(version) && SafeIdentifier.isAbsolutePath(path)
    }
}
