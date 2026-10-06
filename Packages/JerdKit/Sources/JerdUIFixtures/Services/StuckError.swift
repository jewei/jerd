import Foundation
import JerdServiceKit

/// A stop that timed out. The caller keeps the stuck state, then rethrows.
struct StuckError: Error, LocalizedError {
    let state: ServiceState
    let reason: String
    var errorDescription: String? { reason }
}
