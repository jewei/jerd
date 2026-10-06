import Foundation
import JerdSystem

/// The first result of the probe call.
///
/// `@unchecked Sendable` (check tool only): `stored` is read and written only under `lock`.
final class ResultBox: @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var stored: Result<LoopbackListenerPair, any Error>?

    var result: Result<LoopbackListenerPair, any Error>? { lock.withLock { stored } }

    func finish(_ value: Result<LoopbackListenerPair, any Error>) {
        let first = lock.withLock {
            guard stored == nil else { return false }
            stored = value
            return true
        }
        if first { done.signal() }
    }
}
