import Darwin
import Foundation
import JerdFoundation

/// The live FPM ping: one bounded FastCGI exchange over the pool's Unix socket.
///
/// One deadline covers the whole exchange, connect included. Every wait polls in 50 ms slices,
/// so cancellation stops it quickly. A full listen backlog (`EAGAIN`) is retried until the deadline.
/// The blocking exchange runs on its own thread, because `EngineRunner.isHealthy` pings every pool
/// at once and a blocked cooperative thread stops other tasks.
public struct FastCGIPing: FPMPinging {
    /// The default budget of one ping.
    public static let defaultTimeout: Duration = .seconds(3)
    /// The poll slice of every wait.
    static let slice: Int32 = 50

    private let timeout: Duration

    public init(timeout: Duration = defaultTimeout) {
        self.timeout = timeout
    }

    public func ping(socket: URL) async throws {
        let deadline = ContinuousClock.now + timeout
        let cancellation = PingCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let thread = Thread {
                    continuation.resume(
                        with: Result { try Self.exchange(socket: socket, until: deadline, cancellation: cancellation) })
                }
                thread.name = "dev.jerd.fpm-ping"
                thread.start()
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func exchange(
        socket path: URL, until deadline: ContinuousClock.Instant, cancellation: PingCancellation
    ) throws {
        try cancellation.check()
        let connection = try UnixStreamConnection.open(path: path.path, deadline: deadline, cancellation: cancellation)
        defer { connection.close() }
        try connection.send(FastCGIPingCodec.request())
        var decoder = FastCGIResponseDecoder()
        while true {
            let bytes = try connection.receive()
            guard !bytes.isEmpty else {
                throw JerdError.processFailed("FPM closed its readiness connection without a complete response.")
            }
            if try decoder.consume(bytes) { return }
        }
    }
}
