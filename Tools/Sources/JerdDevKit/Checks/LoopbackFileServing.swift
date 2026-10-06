import Foundation

/// Serves the files of one folder over HTTP on `127.0.0.1` only, for the Sparkle test feed.
/// `LoopbackFileServer` is the live type; tests of the harness flow use a fake.
protocol LoopbackFileServing: Sendable {
    /// Starts serving `folder` on a free loopback port and returns the base URL, for example
    /// `http://127.0.0.1:52011/`.
    func start(serving folder: URL) async throws -> URL
    /// Stops listening and closes every connection.
    func stop() async
}
