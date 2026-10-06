import os

/// The bucket names that the running RustFS listed last: the per-launch state of storage.
///
/// The readiness probe and bucket operations write it. A start and a user Stop clear it, so a
/// new launch never shows the names of an earlier one, and a snapshot shows it only while RustFS
/// runs. All per-launch state lives here, so a stop hook of the
/// shared lifecycle can release it with one call to `clear()`.
final class ListedBuckets: Sendable {
    private let names = OSAllocatedUnfairLock<Set<String>>(initialState: [])

    var current: Set<String> { names.withLock { $0 } }

    func replace(with listed: Set<String>) { names.withLock { $0 = listed } }

    func insert(_ name: String) { names.withLock { _ = $0.insert(name) } }

    func clear() { names.withLock { $0 = [] } }
}
