import Foundation
import JerdFoundation
import os

/// Collects the answers of `S3Transport` data tasks in chunks, with a size bound, and refuses
/// every redirect.
///
/// A declared or streamed body above the limit cancels the task at once, so memory use stays at
/// the limit. A redirect is not followed: the 3xx answer itself completes the task.
final class S3SessionDelegate: NSObject, URLSessionDataDelegate, Sendable {
    private struct Pending: Sendable {
        let continuation: CheckedContinuation<S3Response, any Error>
        var body = Data()
        var response: HTTPURLResponse?
        var exceeded = false
    }

    let limit: Int
    private let pending = OSAllocatedUnfairLock<[Int: Pending]>(initialState: [:])

    init(limit: Int) { self.limit = limit }

    /// Registers the continuation of a task before the task resumes.
    func register(_ task: URLSessionTask, continuation: CheckedContinuation<S3Response, any Error>) {
        pending.withLock { $0[task.taskIdentifier] = Pending(continuation: continuation) }
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let allowed = pending.withLock { tasks -> Bool in
            guard response.expectedContentLength <= Int64(limit) else {
                tasks[dataTask.taskIdentifier]?.exceeded = true
                return false
            }
            tasks[dataTask.taskIdentifier]?.response = response as? HTTPURLResponse
            return true
        }
        completionHandler(allowed ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let limit = limit
        let exceeded = pending.withLock { tasks -> Bool in
            guard var entry = tasks[dataTask.taskIdentifier] else { return false }
            entry.exceeded = entry.exceeded || entry.body.count + data.count > limit
            if !entry.exceeded { entry.body.append(data) }
            tasks[dataTask.taskIdentifier] = entry
            return entry.exceeded
        }
        if exceeded { dataTask.cancel() }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let entry = pending.withLock({ $0.removeValue(forKey: task.taskIdentifier) }) else { return }
        entry.continuation.resume(with: Self.result(of: entry, error: error))
    }

    private static func result(of entry: Pending, error: (any Error)?) -> Result<S3Response, any Error> {
        if entry.exceeded { return .failure(StorageMessages.responseTooLarge) }
        if let error {
            if (error as? URLError)?.code == .cancelled { return .failure(CancellationError()) }
            return .failure(
                JerdError.unavailable("Cannot reach the local storage service. \(error.localizedDescription)"))
        }
        guard let response = entry.response else { return .failure(StorageMessages.invalidResponse) }
        return .success(S3Response(status: response.statusCode, body: entry.body))
    }
}
