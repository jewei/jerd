import Foundation
import JerdFoundation
import JerdRuntimes
import Testing
import os

@Suite struct URLSessionFetcherTests {
    private let fetcher = FakeURLProtocol.fetcher()

    @Test func dataArrivesWithTheJerdUserAgentAndNoAuthorization() async throws {
        let url = testURL()
        FakeURLProtocol.register(url, .init(chunks: [Data("hello ".utf8), Data("world".utf8)]))
        #expect(try await fetcher.data(from: url, limit: 100) == Data("hello world".utf8))
        let request = try #require(FakeURLProtocol.received(url).first)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Jerd/9.9 runtime-updates")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func transferStopsAsSoonAsTheLimitIsExceeded() async throws {
        let url = testURL()
        let chunks = Array(repeating: Data(repeating: 7, count: 1_000), count: 50)
        FakeURLProtocol.register(url, .init(chunks: chunks, announcedLength: 0))
        await #expect(throws: JerdError.invalid("The download exceeds its size limit or is empty.")) {
            try await fetcher.data(from: url, limit: 2_500)
        }
    }

    @Test func announcedSizeAboveTheLimitIsRefusedBeforeAnyByte() async throws {
        let url = testURL()
        FakeURLProtocol.register(url, .init(chunks: [Data(count: 10)], announcedLength: 10_000))
        await #expect(throws: JerdError.invalid("The download exceeds its size limit or is empty.")) {
            try await fetcher.data(from: url, limit: 100)
        }
    }

    @Test func emptyResponseIsRefused() async throws {
        let url = testURL()
        FakeURLProtocol.register(url, .init(chunks: []))
        await #expect(throws: JerdError.invalid("The download exceeds its size limit or is empty.")) {
            try await fetcher.data(from: url, limit: 100)
        }
    }

    @Test(arguments: [
        (403, "The update source limit was reached. Try again later."),
        (429, "The update source limit was reached. Try again later."),
        (404, "The update source returned HTTP 404."), (500, "The update source returned HTTP 500."),
    ])
    func statusCodesMapToUserMessages(_ status: Int, _ message: String) async throws {
        let url = testURL()
        FakeURLProtocol.register(url, .init(status: status, chunks: [Data("x".utf8)]))
        await #expect(throws: JerdError.unavailable(message)) { try await fetcher.data(from: url, limit: 100) }
    }

    @Test func allowedRedirectIsFollowedWithoutCredentials() async throws {
        let start = testURL()
        let target = testURL("release-assets.githubusercontent.com")
        FakeURLProtocol.register(start, .init(redirect: target))
        FakeURLProtocol.register(target, .init(chunks: [Data("asset".utf8)]))
        #expect(try await fetcher.data(from: start, limit: 100) == Data("asset".utf8))
        let followed = try #require(FakeURLProtocol.received(target).first)
        #expect(followed.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(followed.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func redirectToAnotherHostIsRefused() async throws {
        let start = testURL()
        let target = testURL("github.com.evil.test")
        FakeURLProtocol.register(start, .init(redirect: target))
        FakeURLProtocol.register(target, .init(chunks: [Data("evil".utf8)]))
        await #expect(throws: JerdError.invalid("The update source has an unsupported download URL.")) {
            try await fetcher.data(from: start, limit: 100)
        }
        #expect(FakeURLProtocol.received(target).isEmpty)
    }

    @Test(arguments: [
        "http://github.com/a", "https://github.com.evil.test/a", "https://name:password@github.com/a",
        "https://github.com:8443/a", "file:///tmp/runtime",
    ])
    func urlsOutsideTheAllowlistAreRefusedBeforeAnyRequest(_ text: String) async throws {
        let url = try #require(URL(string: text))
        await #expect(throws: JerdError.invalid("The update source has an unsupported download URL.")) {
            try await fetcher.data(from: url, limit: 100)
        }
    }

    @Test func downloadWritesAPrivateFileAndReportsWholePercents() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let url = testURL()
        FakeURLProtocol.register(url, .init(chunks: Array(repeating: Data(repeating: 1, count: 250), count: 4)))
        let seen = OSAllocatedUnfairLock(initialState: [Double]())
        let destination = folder.path("download")
        let count = try await fetcher.download(from: url, to: destination, limit: 1_000) { value in
            seen.withLock { $0.append(value) }
        }
        #expect(count == 1_000)
        #expect(permissions(destination) == 0o600)
        // URLSession can join chunks, so only the form of the reports is fixed: rising whole percents to 100.
        let values = seen.withLock { $0 }
        #expect(values.last == 1.0)
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 < $1 })
        #expect(values.allSatisfy { ($0 * 100).rounded() == $0 * 100 })
    }

    @Test func failedDownloadLeavesNoFileAndNeverReplacesAnExistingOne() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let url = testURL()
        FakeURLProtocol.register(url, .init(chunks: [Data(count: 600)], announcedLength: 0))
        let destination = folder.path("download")
        await #expect(throws: JerdError.self) {
            try await fetcher.download(from: url, to: destination, limit: 100) { _ in }
        }
        #expect(FileProbe.presence(at: destination) == .absent)
        let existing = try folder.write("keep", to: "existing")
        FakeURLProtocol.register(url, .init(chunks: [Data("new".utf8)]))
        await #expect(throws: JerdError.self) {
            try await fetcher.download(from: url, to: existing, limit: 100) { _ in }
        }
        #expect(try String(contentsOf: existing, encoding: .utf8) == "keep")
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .cannotFindHost, .timedOut, .networkConnectionLost])
    func offlineTransferNamesTheNetworkConnection(_ code: URLError.Code) async throws {
        let url = testURL()
        FakeURLProtocol.register(url, .init(failure: code))
        let offline = JerdError.unavailable(
            "Jerd cannot reach the download server. Check the network connection, then try again.")
        await #expect(throws: offline) { try await fetcher.data(from: url, limit: 100) }
    }

    @Test func otherTransportFailureKeepsTheSystemText() async throws {
        let url = testURL()
        FakeURLProtocol.register(url, .init(failure: .badServerResponse))
        let error = await #expect(throws: JerdError.self) { try await fetcher.data(from: url, limit: 100) }
        #expect(error?.message.hasPrefix("The download failed: ") == true)
    }

    @Test func fullDiskIsRecognizedInEveryErrorForm() {
        #expect(DiskSpace.isOutOfSpace(POSIXError(.ENOSPC)))
        #expect(DiskSpace.isOutOfSpace(CocoaError(.fileWriteOutOfSpace)))
        #expect(DiskSpace.isOutOfSpace(NSError(domain: NSPOSIXErrorDomain, code: Int(EDQUOT))))
        #expect(DiskSpace.isOutOfSpace(JerdError.unavailable("Cannot copy x (\(SystemError.describe(ENOSPC)))")))
        #expect(!DiskSpace.isOutOfSpace(JerdError.unavailable("Cannot copy x (\(SystemError.describe(EACCES)))")))
        #expect(!DiskSpace.isOutOfSpace(POSIXError(.EACCES)))
        #expect(!DiskSpace.isOutOfSpace(CancellationError()))
    }

    @Test func userAgentNamesTheAppVersion() {
        #expect(URLSessionFetcher.userAgent(appVersion: "0.2.0") == "Jerd/0.2.0 runtime-updates")
        #expect(URLSessionFetcher.userAgent(appVersion: nil) == "Jerd runtime-updates")
    }
}
