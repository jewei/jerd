import Foundation

/// The message of a failed read, kept as evidence.
struct RecoveryReadFailure: Error, Equatable, Sendable {
    let message: String
}
