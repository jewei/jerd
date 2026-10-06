import Foundation

/// The live HTTP transport to the local RustFS service.
///
/// It uses one ephemeral session for its whole life: no proxies, no cookies, no cache, no
/// redirects, a 5-second request timeout, an 8-second resource timeout, and bodies of at most
/// 4 MiB. Credentials stay in signed headers and never appear in URLs.
public final class S3Transport: S3Sending {
    /// The largest answer body.
    public static let responseLimit = 4 * 1_048_576

    private let session: URLSession
    private let delegate: S3SessionDelegate

    public init(responseLimit: Int = S3Transport.responseLimit) {
        delegate = S3SessionDelegate(limit: responseLimit)
        session = URLSession(configuration: Self.configuration(), delegate: delegate, delegateQueue: nil)
    }

    deinit {
        // The session keeps its delegate until it is invalidated.
        session.invalidateAndCancel()
    }

    public func send(_ request: URLRequest) async throws -> S3Response {
        let task = session.dataTask(with: request)
        let delegate = delegate
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.register(task, continuation: continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// The session settings of the transport.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 0, kCFNetworkProxiesHTTPSEnable as String: 0,
            kCFNetworkProxiesSOCKSEnable as String: 0,
        ]
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }
}
