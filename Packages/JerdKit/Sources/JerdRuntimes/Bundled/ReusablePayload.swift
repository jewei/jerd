import Foundation
import JerdManifest

/// A verified payload folder of an on-demand pin that an earlier copy of Jerd installed from its
/// bundle. Jerd registers it again instead of downloading the pin.
public struct ReusablePayload: Equatable, Sendable {
    /// The folder name, which is the runtime ID.
    public let id: String
    public let kind: RuntimeKind
    /// The version that the runtime reports.
    public let version: String
    public let directory: URL

    public init(id: String, kind: RuntimeKind, version: String, directory: URL) {
        self.id = id
        self.kind = kind
        self.version = version
        self.directory = directory
    }
}
