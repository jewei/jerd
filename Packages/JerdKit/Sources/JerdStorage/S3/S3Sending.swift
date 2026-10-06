import Foundation

/// Sends one HTTP request to the local RustFS service. The live type is `S3Transport`.
public protocol S3Sending: Sendable {
    /// The status and the complete body. A non-2xx status is not an error here.
    /// - Throws: when the server cannot be reached, the answer is not HTTP, or the body is too large.
    func send(_ request: URLRequest) async throws -> S3Response
}
