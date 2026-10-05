import Darwin
import Foundation
import JerdFoundation

/// The live `HTTPFetching`: one ephemeral URLSession per transfer, no cookies, no credentials,
/// no cache, a 60-second request timeout and a 15-minute resource timeout. No `Authorization`
/// header is ever sent.
public struct URLSessionFetcher: HTTPFetching {
    /// Builds the session configuration of each transfer. Tests add a fake `URLProtocol`.
    public typealias ConfigurationFactory = @Sendable () -> URLSessionConfiguration

    private let allowlist: HostAllowlist
    private let userAgent: String
    private let makeConfiguration: ConfigurationFactory

    public init(
        userAgent: String = Self.userAgent(appVersion: nil), allowlist: HostAllowlist = .runtimeSources,
        configuration: @escaping ConfigurationFactory = Self.ephemeralConfiguration
    ) {
        self.userAgent = userAgent
        self.allowlist = allowlist
        makeConfiguration = configuration
    }

    /// `Jerd/<version> runtime-updates`, or `Jerd runtime-updates` without a version.
    public static func userAgent(appVersion: String?) -> String {
        appVersion.map { "Jerd/\($0) runtime-updates" } ?? "Jerd runtime-updates"
    }

    /// The private session settings of D2.
    public static func ephemeralConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 900
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    public func data(from url: URL, limit: Int) async throws -> Data {
        try await transfer(url, limit: Int64(limit), sink: .memory, progress: nil).data
    }

    public func download(
        from url: URL, to destination: URL, limit: Int64, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        try allowlist.validate(url)
        let descriptor = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw JerdError.unavailable("Cannot create \(destination.path) (\(SystemError.describe(errno))).")
        }
        var completed = false
        defer {
            close(descriptor)
            if !completed { unlink(destination.path) }
        }
        let result = try await transfer(url, limit: limit, sink: .file(descriptor), progress: progress)
        guard fsync(descriptor) == 0 else { throw TransferFailure.write(errno).error }
        completed = true
        return result.count
    }

    private func transfer(
        _ url: URL, limit: Int64, sink: TransferSink, progress: (@Sendable (Double) -> Void)?
    ) async throws -> TransferResult {
        try allowlist.validate(url)
        try Task.checkCancellation()
        let delegate = TransferDelegate(allowlist: allowlist, limit: limit, sink: sink, progress: progress)
        let session = URLSession(configuration: makeConfiguration(), delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.begin(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }
}
