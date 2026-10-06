import Foundation
import JerdRuntimes
import os

/// An `HTTPFetching` whose `data` calls wait until the test opens the gate. A cancelled call
/// throws `CancellationError` and is recorded.
final class GatedFetcher: HTTPFetching, Sendable {
    private struct State {
        var isOpen = false
        var requests = 0
        var cancellations = 0
    }

    private let response: Data
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(_ response: Data) { self.response = response }

    var requestCount: Int { state.withLock { $0.requests } }
    var wasCancelled: Bool { state.withLock { $0.cancellations > 0 } }

    func open() { state.withLock { $0.isOpen = true } }

    func data(from url: URL, limit: Int) async throws -> Data {
        state.withLock { $0.requests += 1 }
        while !state.withLock({ $0.isOpen }) {
            do {
                try await Task.sleep(for: .milliseconds(1))
            } catch {
                state.withLock { $0.cancellations += 1 }
                throw error
            }
        }
        return response
    }

    func download(
        from url: URL, to destination: URL, limit: Int64, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        throw CancellationError()
    }
}
