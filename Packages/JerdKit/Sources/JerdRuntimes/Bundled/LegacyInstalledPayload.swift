import Foundation
import JerdManifest

/// A payload folder that an older Jerd installed, after `LegacyPayloadVerifier` checked it.
///
/// Older service records name such a folder by its ID, for example `mysql-8.4.11-arm64`.
public struct LegacyInstalledPayload: Equatable, Sendable {
    /// The folder name, which older records use as the runtime ID.
    public let id: String
    public let group: PayloadGroup
    public let directory: URL
    /// The legacy receipt that the folder matched.
    public let receipt: LegacyPayloadReceipt

    public init(id: String, group: PayloadGroup, directory: URL, receipt: LegacyPayloadReceipt) {
        self.id = id
        self.group = group
        self.directory = directory
        self.receipt = receipt
    }
}
