import Foundation
import JerdFoundation
import JerdRuntimes
import Testing
import os

@Suite struct MetadataCacheTests {
    @Test func freshEntriesAreServedFromMemoryAndExpireAfterTheirLifetime() async throws {
        let url = testURL()
        let fetcher = FakeFetcher([url: Data("v1".utf8)])
        let clock = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 0))
        let cache = MetadataCache(fetcher: fetcher, lifetime: 300) { clock.withLock { $0 } }
        #expect(try await cache.data(url) == Data("v1".utf8))
        fetcher.set(url, Data("v2".utf8))
        clock.withLock { $0 = Date(timeIntervalSince1970: 299) }
        #expect(try await cache.data(url) == Data("v1".utf8))
        clock.withLock { $0 = Date(timeIntervalSince1970: 300) }
        #expect(try await cache.data(url) == Data("v2".utf8))
        #expect(fetcher.requests.count == 2)
    }

    @Test func concurrentRequestsForOneURLShareOneFetch() async throws {
        let url = testURL()
        let fetcher = FakeFetcher([url: Data("shared".utf8)], delay: .milliseconds(50))
        let cache = MetadataCache(fetcher: fetcher)
        async let first = cache.data(url)
        async let second = cache.data(url)
        #expect(try await [first, second] == [Data("shared".utf8), Data("shared".utf8)])
        #expect(fetcher.requests.count == 1)
    }

    /// Waits until `count` callers wait for the running fetch of `url`.
    private func waitForWaiters(_ count: Int, of url: URL, in cache: MetadataCache) async throws {
        while await cache.waiterCount(for: url) != count { try await Task.sleep(for: .milliseconds(1)) }
    }

    /// A cancelled waiter stops waiting at once, and the fetch goes on for the waiter that remains.
    @Test func cancelledWaiterDoesNotCancelTheSharedFetchOfTheOthers() async throws {
        let url = testURL()
        let fetcher = GatedFetcher(Data("shared".utf8))
        let cache = MetadataCache(fetcher: fetcher)
        let first = Task { try await cache.data(url) }
        let second = Task { try await cache.data(url) }
        try await waitForWaiters(2, of: url, in: cache)
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(fetcher.requestCount == 1 && !fetcher.wasCancelled)
        fetcher.open()
        #expect(try await second.value == Data("shared".utf8))
        #expect(fetcher.requestCount == 1)
    }

    @Test func fetchWithoutWaitersIsCancelledAndTheNextRequestFetchesAgain() async throws {
        let url = testURL()
        let fetcher = GatedFetcher(Data("fresh".utf8))
        let cache = MetadataCache(fetcher: fetcher)
        let waiter = Task { try await cache.data(url) }
        try await waitForWaiters(1, of: url, in: cache)
        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        while !fetcher.wasCancelled { try await Task.sleep(for: .milliseconds(1)) }
        let again = Task { try await cache.data(url) }
        try await waitForWaiters(1, of: url, in: cache)
        fetcher.open()
        #expect(try await again.value == Data("fresh".utf8))
        #expect(fetcher.requestCount == 2)
    }

    @Test func errorsAreNotCached() async throws {
        let url = testURL()
        let fetcher = FakeFetcher()
        let cache = MetadataCache(fetcher: fetcher)
        await #expect(throws: JerdError.self) { try await cache.data(url) }
        fetcher.set(url, Data("ok".utf8))
        #expect(try await cache.data(url) == Data("ok".utf8))
    }

    @Test func oldestEntryIsEvictedAboveCapacity() async throws {
        let urls = [testURL(), testURL(), testURL()]
        let fetcher = FakeFetcher(Dictionary(uniqueKeysWithValues: urls.map { ($0, Data("x".utf8)) }))
        let clock = OSAllocatedUnfairLock(initialState: 0.0)
        let cache = MetadataCache(fetcher: fetcher, capacity: 2) {
            clock.withLock {
                $0 += 1
                return Date(timeIntervalSince1970: $0)
            }
        }
        for url in urls { _ = try await cache.data(url) }
        _ = try await cache.data(urls[0])
        #expect(fetcher.requests == urls + [urls[0]])
    }

    @Test func textMustBeUTF8() async throws {
        let url = testURL()
        let cache = MetadataCache(fetcher: FakeFetcher([url: Data([0xFF, 0xFE])]))
        await #expect(throws: JerdError.invalid("The update source has invalid text.")) { try await cache.text(url) }
    }
}
