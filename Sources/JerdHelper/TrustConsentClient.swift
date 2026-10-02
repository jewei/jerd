import Foundation
import JerdCore

/// Requests consent over the same mutually authenticated XPC connection.
final class TrustConsentClient: @unchecked Sendable {
    private weak var connection: NSXPCConnection?
    init(connection: NSXPCConnection) { self.connection = connection }

    func change(_ request: TrustConsentRequest) async throws -> Int32 {
        guard let connection else { throw JerdError.approvalInterrupted("The app connection closed before certificate approval.") }
        let data = try JSONEncoder().encode(request)
        return try await withCheckedThrowingContinuation { continuation in
            let reply = ConsentReply(continuation)
            let remote = connection.remoteObjectProxyWithErrorHandler { @Sendable error in
                reply.resolve(.failure(JerdError.approvalInterrupted("The app connection closed during certificate approval: \(error.localizedDescription)")))
            }
            guard let proxy = remote as? any JerdTrustConsentProtocol else {
                reply.resolve(.failure(JerdError.approvalInterrupted("The certificate consent interface is unavailable.")))
                return
            }
            proxy.changeTrust(data) { status in reply.resolve(.success(status)) }
        }
    }
}

private final class ConsentReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int32, any Error>?
    init(_ continuation: CheckedContinuation<Int32, any Error>) { self.continuation = continuation }
    func resolve(_ result: Result<Int32, any Error>) {
        let current = lock.withLock { let result = continuation; continuation = nil; return result }
        current?.resume(with: result)
    }
}
