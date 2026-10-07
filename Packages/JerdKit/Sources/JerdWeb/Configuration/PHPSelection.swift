import Foundation

/// The PHP runtime of one site: the default runtime, or one pinned runtime.
///
/// The synthesized coding is the saved form: `{"followDefault":{}}` or `{"pinned":{"_0":"<UUID>"}}`.
public enum PHPSelection: Codable, Hashable, Sendable {
    case followDefault
    case pinned(UUID)
}
