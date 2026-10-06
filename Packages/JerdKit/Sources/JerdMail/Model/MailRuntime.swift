import Foundation
import JerdServiceKit

/// An installed Mailpit runtime folder. Saved in `mail/settings.json` and as the inbox identity
/// (`inbox/runtime.json`, `inbox/initialized.json`). Equality includes the path.
public struct MailRuntime: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let version: String
    /// The absolute runtime folder that contains `mailpit`.
    public let path: String

    public init(id: String, version: String, path: String) {
        self.id = id
        self.version = version
        self.path = path
    }

    /// The executable `<path>/mailpit`.
    public var executable: URL {
        URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("mailpit")
    }

    /// True when the ID and version are safe identifiers and the path is absolute without
    /// control characters.
    public var isValid: Bool {
        SafeIdentifier.isValid(id) && SafeIdentifier.isValid(version) && SafeIdentifier.isAbsolutePath(path)
    }
}
