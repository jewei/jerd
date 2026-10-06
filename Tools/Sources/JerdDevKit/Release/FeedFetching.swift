import Foundation

/// Reads the public update feed at the URL that installed apps use, so publication checks what users
/// get, not only the GitHub API (fixes spec G 8.1 #8).
protocol FeedFetching: Sendable {
    /// The bytes at `url`.
    /// - Throws: `DevFailure.checkFailed` for a transport error, an HTTP status other than 200, or a large answer.
    func feed(at url: URL) async throws -> Data
}

/// Fetches over HTTPS without any cache, so a stale local copy can never pass.
struct URLSessionFeedFetcher: FeedFetching {
    /// The feed grows with every release, but stays far below this size.
    static let sizeLimit = 4_000_000

    func feed(at url: URL) async throws -> Data {
        guard url.scheme == "https" else { throw DevFailure.checkFailed("The feed URL must use HTTPS.") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw DevFailure.checkFailed("Could not fetch \(url.absoluteString): \(error.localizedDescription)")
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= Self.sizeLimit else {
            throw DevFailure.checkFailed("\(url.absoluteString) did not return the feed.")
        }
        return data
    }
}
