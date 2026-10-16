import Foundation
import JerdTunnels
import os

/// Answers Cloudflare API requests from a table keyed by "METHOD /path", and records each request.
/// A key with several answers gives them in order and then repeats the last one. A request without
/// an answer gets a 500 failure envelope.
final class FakeCloudflareTransport: CloudflareTransporting {
    struct Sent: Equatable {
        let method: String
        let path: String
        let query: String?
        let authorization: String?
        let body: String?
    }

    private let state = OSAllocatedUnfairLock(initialState: (answers: [String: [(Int, String)]](), sent: [Sent]()))

    static let account = String(repeating: "a", count: 32)
    static let zone = String(repeating: "b", count: 32)
    static let record = String(repeating: "c", count: 32)
    static let tunnel = UUID(uuidString: TokenSamples.tunnelID)!
    static var tunnelPath: String { "/client/v4/accounts/\(account)/cfd_tunnel/\(tunnel.uuidString.lowercased())" }

    func answer(_ key: String, status: Int = 200, _ json: String) {
        state.withLock { $0.answers[key] = [(status, json)] }
    }

    /// Answers the next request of `key` with `json`, then the earlier answers.
    func answerNext(_ key: String, status: Int = 200, _ json: String) {
        state.withLock { $0.answers[key, default: []].insert((status, json), at: 0) }
    }

    var sent: [Sent] { state.withLock { $0.sent } }
    var keys: [String] { sent.map { "\($0.method) \($0.path)" } }

    func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        guard let url = request.url else { throw URLError(.badURL) }
        let sent = Sent(
            method: request.httpMethod ?? "", path: url.path, query: url.query,
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            body: request.httpBody.map { String(decoding: $0, as: UTF8.self) })
        let answer = state.withLock { state -> (Int, String)? in
            state.sent.append(sent)
            let key = "\(sent.method) \(sent.path)"
            guard var queue = state.answers[key], let first = queue.first else { return nil }
            if queue.count > 1 { queue.removeFirst() }
            state.answers[key] = queue
            return first
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

    /// A record or tunnel JSON as Cloudflare returns it.
    static var route: String {
        #"{"id":"\#(record)","type":"CNAME","content":"\#(tunnel.uuidString.lowercased()).cfargotunnel.com"}"#
    }

    /// Answers for a whole Remove of a live tunnel with its route.
    func answerRemove(route: String = FakeCloudflareTransport.route, deletedAt: String = "null") {
        let recordPath = "/client/v4/zones/\(Self.zone)/dns_records/\(Self.record)"
        answer("GET \(recordPath)", Self.success(route))
        answer("DELETE \(recordPath)", Self.success("null"))
        answer("GET \(Self.tunnelPath)", Self.success(#"{"id":"\#(Self.tunnel)","deleted_at":\#(deletedAt)}"#))
        answer("DELETE \(Self.tunnelPath)/connections", Self.success("null"))
        answer("DELETE \(Self.tunnelPath)", Self.success("null"))
    }

    static let exampleZone = CloudflareZone(id: zone, name: "example.com", accountID: account)
}
