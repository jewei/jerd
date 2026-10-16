import Foundation

/// HTTPS to the Cloudflare API: an ephemeral session without cookies, cache, proxies from a
/// redirect, or redirects, so the API token goes only to `api.cloudflare.com`.
public struct CloudflareTransport: CloudflareTransporting {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: RedirectRefusal(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    private final class RedirectRefusal: NSObject, URLSessionTaskDelegate {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? { nil }
    }
}
