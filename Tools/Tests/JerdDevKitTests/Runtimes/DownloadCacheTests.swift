import Foundation
import JerdFoundation
import Testing

@testable import JerdDevKit

@Suite("Download cache")
struct DownloadCacheTests {
    static let url = URL(string: "https://github.com/example/archive.tar.gz")!
    static let bytes = Data("archive".utf8)
    static let digest = FileDigest.hexSHA256(of: bytes)

    private func cache(_ folder: URL, fetcher: FakeFetcher, digest: String = digest) -> DownloadCache {
        DownloadCache(folder: folder.appending(path: "downloads"), upstream: fetcher, digests: [Self.url: digest])
    }

    private func download(_ cache: DownloadCache, into folder: URL, name: String) async throws -> URL {
        let destination = folder.appending(path: name)
        _ = try await cache.download(from: Self.url, to: destination, limit: 100) { _ in }
        return destination
    }

    @Test("A pinned download is stored once and then served from the cache")
    func reusesCachedDownload() async throws {
        let folder = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fetcher = FakeFetcher(files: [Self.url: Self.bytes])
        let cache = cache(folder, fetcher: fetcher)
        _ = try await download(cache, into: folder, name: "first")
        let second = try await download(cache, into: folder, name: "second")
        #expect(fetcher.requested == [Self.url])
        #expect(try Data(contentsOf: second) == Self.bytes)
        let mode = try FileManager.default.attributesOfItem(atPath: second.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test("A download with another digest never enters the cache")
    func refusesWrongDigest() async throws {
        let folder = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fetcher = FakeFetcher(files: [Self.url: Self.bytes])
        let cache = cache(folder, fetcher: fetcher, digest: String(repeating: "0", count: 64))
        _ = try await download(cache, into: folder, name: "first")
        _ = try await download(cache, into: folder, name: "second")
        #expect(fetcher.requested.count == 2)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "downloads").path))
    }

    @Test("A changed cache file is removed and downloaded again")
    func replacesChangedCacheFile() async throws {
        let folder = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try TestFixtures.write("tampered", to: "downloads/\(Self.digest)", in: folder)
        let fetcher = FakeFetcher(files: [Self.url: Self.bytes])
        let result = try await download(cache(folder, fetcher: fetcher), into: folder, name: "file")
        #expect(fetcher.requested == [Self.url])
        #expect(try Data(contentsOf: result) == Self.bytes)
        #expect(try Data(contentsOf: folder.appending(path: "downloads/\(Self.digest)")) == Self.bytes)
    }

    @Test("A pinned small file is cached under its digest; another file never enters the cache")
    func cachesPinnedData() async throws {
        let folder = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let fetcher = FakeFetcher(files: [Self.url: Self.bytes])
        let cache = cache(folder, fetcher: fetcher)
        #expect(try await cache.data(from: Self.url, limit: 100) == Self.bytes)
        #expect(try await cache.data(from: Self.url, limit: 100) == Self.bytes)
        #expect(fetcher.requested == [Self.url])
        #expect(try Data(contentsOf: folder.appending(path: "downloads/\(Self.digest)")) == Self.bytes)
        let other = DownloadCache(
            folder: folder.appending(path: "other"), upstream: fetcher,
            digests: [Self.url: String(repeating: "0", count: 64)])
        _ = try await other.data(from: Self.url, limit: 100)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "other").path))
    }

    @Test("A URL without a pinned digest passes through")
    func passesThroughUnpinned() async throws {
        let folder = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let other = URL(string: "https://github.com/example/other")!
        let fetcher = FakeFetcher(files: [other: Self.bytes])
        let cache = DownloadCache(folder: folder.appending(path: "downloads"), upstream: fetcher, digests: [:])
        _ = try await cache.download(from: other, to: folder.appending(path: "a"), limit: 100) { _ in }
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "downloads").path))
    }

    @Test("The digests come from every archive pin and support source")
    func digestsOfCatalog() throws {
        let catalog = try PayloadFixtures.catalog()
        let digests = DownloadCache.digests(of: catalog)
        #expect(
            digests.count
                == catalog.pins.compactMap(\.archive).count + catalog.supportSources.count
                + catalog.pins.compactMap(\.signature).count)
        let signature = try #require(try PayloadFixtures.pin(.mysql).signature)
        #expect(digests[signature.url] == signature.sha256)
        #expect(digests[try #require(catalog.supportSources["xz"]).archive.url] != nil)
    }
}
