import Foundation
import JerdFoundation

/// A short-lived memory cache of publisher metadata (release lists, checksums, pages).
///
/// Entries live for `lifetime` (5 minutes). Concurrent requests for one URL share one fetch.
/// Errors are not cached. At most `capacity` entries are kept; the oldest goes first.
/// Nothing is written to disk.
public actor MetadataCache {
    /// The largest metadata response. The Caddy release list alone is about 9 MB.
    public static let responseLimit = 24 * 1_048_576

    private struct Entry {
        let date: Date
        let data: Data
    }

    private let fetcher: any HTTPFetching
    private let lifetime: TimeInterval
    private let capacity: Int
    private let now: @Sendable () -> Date
    private var entries: [URL: Entry] = [:]
    private var inFlight: [URL: SharedFetch] = [:]

    public init(
        fetcher: any HTTPFetching, lifetime: TimeInterval = 300, capacity: Int = 32,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fetcher = fetcher
        self.lifetime = lifetime
        self.capacity = capacity
        self.now = now
    }

    /// The bytes at `url`, from the cache when they are fresh.
    ///
    /// A cancelled caller stops waiting at once. The shared fetch stops only when no caller waits
    /// for it any more, so Quit never waits for the network and other callers keep their result.
    public func data(_ url: URL) async throws -> Data {
        if let entry = entries[url], now().timeIntervalSince(entry.date) < lifetime { return entry.data }
        let fetch: SharedFetch
        if let running = inFlight[url], !running.isAbandoned {
            fetch = running
        } else {
            fetch = start(url)
        }
        let waiter = fetch.join()
        return try await fetch.value(for: waiter)
    }

    private func start(_ url: URL) -> SharedFetch {
        let fetch = SharedFetch()
        inFlight[url] = fetch
        let fetcher = fetcher
        fetch.attach(
            Task {
                let result: Result<Data, any Error>
                do {
                    result = .success(try await fetcher.data(from: url, limit: Self.responseLimit))
                } catch {
                    result = .failure(error)
                }
                complete(fetch, for: url, with: result)
            })
        return fetch
    }

    /// Stores a successful result before the waiters resume, so a later caller finds it in the cache.
    private func complete(_ fetch: SharedFetch, for url: URL, with result: Result<Data, any Error>) {
        if inFlight[url] === fetch { inFlight[url] = nil }
        if case .success(let data) = result { store(data, for: url) }
        fetch.finish(result)
    }

    /// The UTF-8 text at `url`.
    /// - Throws: `.invalid("The update source has invalid text.")` for bytes that are not UTF-8.
    public func text(_ url: URL) async throws -> String {
        guard let text = String(data: try await data(url), encoding: .utf8) else {
            throw JerdError.invalid("The update source has invalid text.")
        }
        return text
    }

    private func store(_ data: Data, for url: URL) {
        entries[url] = Entry(date: now(), data: data)
        while entries.count > capacity, let oldest = entries.min(by: { $0.value.date < $1.value.date })?.key {
            entries[oldest] = nil
        }
    }
}
