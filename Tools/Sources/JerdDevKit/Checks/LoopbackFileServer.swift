import Foundation
import Network
import os

/// The live loopback file server: a Network.framework listener that accepts connections only on
/// `127.0.0.1`, answers one request per connection with `StaticFileResponse`, and closes it.
final class LoopbackFileServer: LoopbackFileServing {
    private let queue = DispatchQueue(label: "dev.jerd.check-updates.server")
    private let listener = OSAllocatedUnfairLock<NWListener?>(initialState: nil)

    func start(serving folder: URL) async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        let queue = queue
        listener.newConnectionHandler = { connection in
            Self.serve(connection, folder: folder, queue: queue)
        }
        self.listener.withLock { $0 = listener }
        let port = try await Self.ready(listener, queue: queue)
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else {
            throw DevFailure.checkFailed("The loopback server has no valid URL.")
        }
        return url
    }

    func stop() async {
        listener.withLock {
            $0?.cancel()
            $0 = nil
        }
    }

    /// Waits until the listener has its port, or fails.
    private static func ready(_ listener: NWListener, queue: DispatchQueue) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            @Sendable func finish(_ result: Result<UInt16, any Error>) {
                guard
                    resumed.withLock({ value in
                        defer { value = true }
                        return !value
                    })
                else { return }
                continuation.resume(with: result)
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else {
                        return finish(.failure(DevFailure.checkFailed("The loopback server has no port.")))
                    }
                    finish(.success(port))
                case .failed(let error):
                    finish(.failure(DevFailure.checkFailed("The loopback server failed: \(error)")))
                case .cancelled:
                    finish(.failure(DevFailure.checkFailed("The loopback server stopped before it started.")))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private static func serve(_ connection: NWConnection, folder: URL, queue: DispatchQueue) {
        connection.start(queue: queue)
        receive(connection, head: Data(), folder: folder)
    }

    /// Reads until the request head is complete, then answers and closes the connection.
    private static func receive(_ connection: NWConnection, head: Data, folder: URL) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
            var head = head
            if let data { head.append(data) }
            let ready = StaticFileResponse.isComplete(head) || head.count > StaticFileResponse.headLimit
            guard ready || (error == nil && !isComplete) else { return connection.cancel() }
            guard ready else { return receive(connection, head: head, folder: folder) }
            let response = StaticFileResponse.response(to: head) { name in
                FileManager.default.contents(atPath: folder.appending(path: name).path)
            }
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
