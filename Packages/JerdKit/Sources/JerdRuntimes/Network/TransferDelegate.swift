import Foundation
import JerdFoundation
import os

/// Enforces the transfer rules while bytes arrive (D4–D8), not after the download.
///
/// A data task delivers every chunk to this delegate, so the byte limit stops the transfer as
/// soon as it is exceeded and progress is real. Redirects and the final URL must pass the
/// allowlist. All mutable state is behind one lock; URLSession calls the delegate on its own
/// serial queue.
final class TransferDelegate: NSObject, URLSessionDataDelegate, Sendable {
    private let allowlist: HostAllowlist
    private let limit: Int64
    private let sink: TransferSink
    private let progress: (@Sendable (Double) -> Void)?
    private let state = OSAllocatedUnfairLock(initialState: TransferState())

    init(allowlist: HostAllowlist, limit: Int64, sink: TransferSink, progress: (@Sendable (Double) -> Void)?) {
        self.allowlist = allowlist
        self.limit = limit
        self.sink = sink
        self.progress = progress
    }

    /// Stores the continuation that the completion resumes exactly once.
    func begin(_ continuation: CheckedContinuation<TransferResult, any Error>) {
        state.withLock { $0.continuation = continuation }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let url = request.url, allowlist.allows(url) else {
            record(.unsupportedURL)
            task.cancel()
            completionHandler(nil)
            return
        }
        var next = request
        next.setValue(nil, forHTTPHeaderField: "Authorization")
        next.setValue(nil, forHTTPHeaderField: "Cookie")
        completionHandler(next)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        if let failure = Self.check(response, allowlist: allowlist, limit: limit) {
            record(failure)
            completionHandler(.cancel)
            return
        }
        let expected = response.expectedContentLength
        state.withLock { $0.expected = expected > 0 ? expected : nil }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let accepted = state.withLock { current -> Bool in
            guard current.failure == nil else { return false }
            current.received += Int64(data.count)
            guard current.received <= limit else {
                current.failure = .tooLarge
                return false
            }
            if case .memory = sink { current.memory.append(data) }
            return true
        }
        guard accepted else { return dataTask.cancel() }
        let code = sink.write(data)
        guard code == 0 else {
            record(.write(code))
            return dataTask.cancel()
        }
        reportProgress()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, outcome) = state.withLock { current in
            defer { current.continuation = nil }
            return (current.continuation, Self.outcome(of: current, error: error))
        }
        continuation?.resume(with: outcome)
    }

    private func record(_ failure: TransferFailure) {
        state.withLock { if $0.failure == nil { $0.failure = failure } }
    }

    /// Reports whole percents, each once, when the server stated the size.
    private func reportProgress() {
        guard let progress else { return }
        let percent = state.withLock { current -> Int? in
            guard let expected = current.expected else { return nil }
            let value = Int(min(100, current.received * 100 / expected))
            guard value != current.lastPercent else { return nil }
            current.lastPercent = value
            return value
        }
        if let percent { progress(Double(percent) / 100) }
    }

    /// D6, D7, and the announced size: checked before any byte is accepted.
    static func check(_ response: URLResponse, allowlist: HostAllowlist, limit: Int64) -> TransferFailure? {
        guard let http = response as? HTTPURLResponse else { return .status(0) }
        guard http.statusCode == 200 else { return .status(http.statusCode) }
        guard let url = response.url else { return .missingURL }
        guard allowlist.allows(url) else { return .unsupportedURL }
        return response.expectedContentLength > limit ? .tooLarge : nil
    }

    /// The user message of a failed transfer. A Mac without a network connection gets the step
    /// that fixes it, not only the system text.
    package static func transferError(_ error: any Error) -> JerdError {
        let offline: Set<URLError.Code> = [
            .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
            .dnsLookupFailed, .timedOut, .dataNotAllowed, .internationalRoamingOff,
        ]
        if let code = (error as? URLError)?.code, offline.contains(code) {
            return .unavailable("Jerd cannot reach the download server. Check the network connection, then try again.")
        }
        return .unavailable("The download failed: \(error.localizedDescription)")
    }

    private static func outcome(of state: TransferState, error: (any Error)?) -> Result<TransferResult, any Error> {
        if let failure = state.failure { return .failure(failure.error) }
        if let error {
            if (error as? URLError)?.code == .cancelled { return .failure(CancellationError()) }
            return .failure(transferError(error))
        }
        guard state.received > 0 else { return .failure(TransferFailure.empty.error) }
        return .success(TransferResult(data: state.memory, count: state.received))
    }
}
