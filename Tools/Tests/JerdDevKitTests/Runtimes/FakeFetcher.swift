import Foundation
import JerdRuntimes
import os

@testable import JerdDevKit

/// Answers downloads with fixed bytes for each URL and counts the requests. It never uses the network.
final class FakeFetcher: HTTPFetching {
    private let files: [URL: Data]
    private let requests = OSAllocatedUnfairLock(initialState: [URL]())

    init(files: [URL: Data]) {
        self.files = files
    }

    var requested: [URL] { requests.withLock { $0 } }

    func data(from url: URL, limit: Int) async throws -> Data {
        requests.withLock { $0.append(url) }
        guard let data = files[url] else { throw DevFailure.checkFailed("No fake file for \(url).") }
        return data
    }

    func download(
        from url: URL, to destination: URL, limit: Int64, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        let data = try await self.data(from: url, limit: Int(limit))
        try data.write(to: destination)
        return Int64(data.count)
    }
}
