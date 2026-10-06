import Foundation
import os

/// The live HTTP transport to the local RustFS service, for one launch.
///
/// It uses one ephemeral session: no proxies, no cookies, no cache, no redirects, a 5-second
/// request timeout, an 8-second resource timeout, and bodies of at most 4 MiB. Credentials stay
/// in signed headers and never appear in URLs. `invalidate()` ends the session when its launch
/// ends; later sends fail with a message, never with a task of an invalidated session.
public final class S3Transport: S3Sending {
    /// The largest answer body.
    public static let responseLimit = 4 * 1_048_576

    private let session: URLSession
    private let delegate: S3SessionDelegate
    /// True after `invalidate()`. The lock also orders task creation before the invalidation.
    private let invalidated = OSAllocatedUnfairLock(initialState: false)

    public init(responseLimit: Int = S3Transport.responseLimit) {
        delegate = S3SessionDelegate(limit: responseLimit)
        session = URLSession(configuration: Self.configuration(), delegate: delegate, delegateQueue: nil)
    }

    deinit {
        // The session keeps its delegate until it is invalidated.
        session.invalidateAndCancel()
    }

    public func send(_ request: URLRequest) async throws -> S3Response {
        let session = session
        let task = try invalidated.withLock { ended -> URLSessionDataTask in
            guard !ended else { throw StorageMessages.sessionEnded }
            return session.dataTask(with: request)
        }
        let delegate = delegate
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    delegate.register(task, continuation: continuation)
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
        } catch is CancellationError where isInvalidated {
            throw StorageMessages.sessionEnded
        }
    }

    /// Cancels every request and ends the session. Later sends throw `sessionEnded`.
    func invalidate() {
        invalidated.withLock { ended in
            guard !ended else { return }
            ended = true
            session.invalidateAndCancel()
        }
    }

    var isInvalidated: Bool { invalidated.withLock { $0 } }

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
