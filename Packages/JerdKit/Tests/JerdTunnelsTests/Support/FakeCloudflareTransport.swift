import Foundation
import JerdTunnels
import os

/// Answers Cloudflare API requests from a table keyed by "METHOD /path", and records each request.
/// A request without an answer gets a 500 failure envelope.
final class FakeCloudflareTransport: CloudflareTransporting {
    struct Sent: Equatable {
        let method: String
        let path: String
        let query: String?
        let authorization: String?
        let body: String?
    }

    private let state = OSAllocatedUnfairLock(initialState: (answers: [String: (Int, String)](), sent: [Sent]()))

    static let account = String(repeating: "a", count: 32)
    static let zone = String(repeating: "b", count: 32)
    static let record = String(repeating: "c", count: 32)
    static let tunnel = UUID(uuidString: TokenSamples.tunnelID)!
    static var tunnelPath: String { "/client/v4/accounts/\(account)/cfd_tunnel/\(tunnel.uuidString.lowercased())" }

    func answer(_ key: String, status: Int = 200, _ json: String) {
        state.withLock { $0.answers[key] = (status, json) }
    }

    var sent: [Sent] { state.withLock { $0.sent } }
    var keys: [String] { sent.map { "\($0.method) \($0.path)" } }

    func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        guard let url = request.url else { throw URLError(.badURL) }
        let sent = Sent(
            method: request.httpMethod ?? "", path: url.path, query: url.query,
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            body: request.httpBody.map { String(decoding: $0, as: UTF8.self) })
        let answer = state.withLock { state in
            state.sent.append(sent)
            return state.answers["\(sent.method) \(sent.path)"]
        }
        let (status, json) = answer ?? (500, Self.failure(code: 1000, message: "No answer"))
        return (status, Data(json.utf8))
    }

    static func success(_ result: String) -> String { #"{"success":true,"errors":[],"result":\#(result)}"# }
    static func failure(code: Int, message: String) -> String {
        #"{"success":false,"errors":[{"code":\#(code),"message":"\#(message)"}],"result":null}"#
    }

    /// Answers for a whole successful create in `example.com`.
    func answerCreate(token: String = TokenSamples.valid) {
        answer("GET /client/v4/zones/\(Self.zone)/dns_records", Self.success("[]"))
        answer("POST /client/v4/accounts/\(Self.account)/cfd_tunnel", Self.success(#"{"id":"\#(Self.tunnel)"}"#))
        answer("GET \(Self.tunnelPath)/token", Self.success(#""\#(token)""#))
        answer("POST /client/v4/zones/\(Self.zone)/dns_records", Self.success(#"{"id":"\#(Self.record)"}"#))
        answer("DELETE \(Self.tunnelPath)", Self.success("null"))
    }

    static let exampleZone = CloudflareZone(id: zone, name: "example.com", accountID: account)
}
