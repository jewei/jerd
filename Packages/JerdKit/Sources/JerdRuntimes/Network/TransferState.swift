import Foundation

/// The mutable state of one transfer. Only `TransferDelegate` changes it, under its lock.
struct TransferState: Sendable {
    var continuation: CheckedContinuation<TransferResult, any Error>?
    var failure: TransferFailure?
    var received: Int64 = 0
    var expected: Int64?
    var lastPercent = -1
    var memory = Data()
    var finished = false
}
