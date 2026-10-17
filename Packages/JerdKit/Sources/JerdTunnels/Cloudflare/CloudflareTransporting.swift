import Foundation

/// Sends one request to the Cloudflare API. Tests use a fake, so they never use the network.
package protocol CloudflareTransporting: Sendable {
    /// The HTTP status and the body.
    func send(_ request: URLRequest) async throws -> (status: Int, body: Data)
}
