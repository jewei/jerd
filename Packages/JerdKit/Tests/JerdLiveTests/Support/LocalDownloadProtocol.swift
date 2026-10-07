import Foundation
import os

/// A local file server inside URLSession: it answers each registered pinned URL with a local file,
/// so the real fetcher, its host allowlist, and the whole pipeline run without the internet.
/// Every other URL fails as unsupported.
final class LocalDownloadProtocol: URLProtocol, @unchecked Sendable {
    // URLSession owns each instance and calls it on one thread. The file table has a lock.
    private static let files = OSAllocatedUnfairLock(initialState: [String: URL]())
    private static let served = OSAllocatedUnfairLock(initialState: [String]())

    static func serve(_ url: URL, from file: URL) { files.withLock { $0[url.absoluteString] = file } }

    /// The URLs that a session requested, in order.
    static var requests: [String] { served.withLock { $0 } }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let client else { return }
        Self.served.withLock { $0.append(url.absoluteString) }
        guard let file = Self.files.withLock({ $0[url.absoluteString] }),
            let handle = try? FileHandle(forReadingFrom: file),
            let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
        else { return client.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)) }
        defer { try? handle.close() }
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": String(size)])
        client.urlProtocol(self, didReceive: response!, cacheStoragePolicy: .notAllowed)
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            client.urlProtocol(self, didLoad: chunk)
        }
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
