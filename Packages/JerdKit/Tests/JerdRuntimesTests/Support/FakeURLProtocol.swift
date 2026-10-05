import Foundation
import JerdRuntimes
import os

/// A scripted HTTP server inside URLSession. Each test registers routes under unique URLs.
final class FakeURLProtocol: URLProtocol, @unchecked Sendable {
    // URLProtocol requires a class; URLSession owns each instance and calls it on one thread.
    // The only shared state is the route table, which a lock protects.

    /// One scripted response.
    struct Route: Sendable {
        var status = 200
        var chunks: [Data] = []
        var announcedLength: Int?
        var redirect: URL?
        var failure: URLError.Code?
    }

    private static let routes = OSAllocatedUnfairLock(initialState: [String: Route]())
    private static let requests = OSAllocatedUnfairLock(initialState: [String: [URLRequest]]())

    static func register(_ url: URL, _ route: Route) { routes.withLock { $0[url.absoluteString] = route } }

    static func received(_ url: URL) -> [URLRequest] { requests.withLock { $0[url.absoluteString] ?? [] } }

    /// A fetcher whose sessions use this protocol only.
    static func fetcher() -> URLSessionFetcher {
        URLSessionFetcher(userAgent: "Jerd/9.9 runtime-updates") {
            let configuration = URLSessionFetcher.ephemeralConfiguration()
            configuration.protocolClasses = [FakeURLProtocol.self]
            return configuration
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let client else { return }
        Self.requests.withLock { $0[url.absoluteString, default: []].append(request) }
        guard let route = Self.routes.withLock({ $0[url.absoluteString] }) else {
            client.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        if let code = route.failure { return client.urlProtocol(self, didFailWithError: URLError(code)) }
        if let target = route.redirect {
            let response = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString])
            var next = URLRequest(url: target)
            next.allHTTPHeaderFields = request.allHTTPHeaderFields
            if let response { client.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response) }
            return
        }
        let length = route.announcedLength ?? route.chunks.reduce(0) { $0 + $1.count }
        let response = HTTPURLResponse(
            url: url, statusCode: route.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": String(length)])
        if let response { client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        for chunk in route.chunks { client.urlProtocol(self, didLoad: chunk) }
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A unique HTTPS URL on an allowed host for one test.
func testURL(_ host: String = "github.com", _ name: String = "file") -> URL {
    URL(string: "https://\(host)/test/\(UUID().uuidString)/\(name)") ?? URL(fileURLWithPath: "/")
}
