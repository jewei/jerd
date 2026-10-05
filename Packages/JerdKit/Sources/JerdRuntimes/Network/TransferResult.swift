import Foundation

/// The bytes and the count of a finished transfer.
struct TransferResult: Sendable {
    let data: Data
    let count: Int64
}
