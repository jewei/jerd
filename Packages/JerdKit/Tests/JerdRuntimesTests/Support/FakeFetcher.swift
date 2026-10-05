import Foundation
import JerdFoundation
import JerdRuntimes
import os

/// An in-memory `HTTPFetching` with scripted responses keyed by URL. It records every request.
final class FakeFetcher: HTTPFetching, Sendable {
    private let responses: OSAllocatedUnfairLock<[URL: Data]>
    private let log = OSAllocatedUnfairLock(initialState: [URL]())
    private let delay: Duration?

    init(_ responses: [URL: Data] = [:], delay: Duration? = nil) {
        self.responses = OSAllocatedUnfairLock(initialState: responses)
        self.delay = delay
    }

    func set(_ url: URL, _ data: Data) { responses.withLock { $0[url] = data } }

    var requests: [URL] { log.withLock { $0 } }

    func data(from url: URL, limit: Int) async throws -> Data {
        log.withLock { $0.append(url) }
        if let delay { try await Task.sleep(for: delay) }
        guard let data = responses.withLock({ $0[url] }) else {
            throw JerdError.unavailable("The update source returned HTTP 404.")
        }
        guard data.count <= limit else { throw JerdError.invalid("The download exceeds its size limit or is empty.") }
        return data
    }

    func download(
        from url: URL, to destination: URL, limit: Int64, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        let data = try await self.data(from: url, limit: Int(limit))
        guard
            FileManager.default.createFile(
                atPath: destination.path, contents: data, attributes: [.posixPermissions: 0o600])
        else { throw JerdError.unavailable("Cannot create \(destination.path).") }
        progress(1)
        return Int64(data.count)
    }
}
