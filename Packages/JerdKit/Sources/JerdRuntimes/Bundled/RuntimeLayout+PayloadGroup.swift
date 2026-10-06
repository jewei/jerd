import Foundation
import JerdFoundation
import JerdManifest

extension RuntimeLayout {
    /// The Application Support folder of the installed payloads of `group`, current and legacy.
    public func payloadDirectory(for group: PayloadGroup) -> URL {
        switch group {
        case .development: developmentRuntimesDirectory
        case .database: databaseRuntimesDirectory
        case .mail: mailRuntimesDirectory
        case .storage: storageRuntimesDirectory
        }
    }
}
