import Foundation
import JerdServiceKitTestSupport
import JerdStorage
import os

/// An in-memory S3 service with RustFS answers. Every S3 request must carry a SigV4
/// `Authorization` header; the console path answers 200.
final class FakeS3Server: S3Sending {
    struct State {
        var buckets: Set<String> = []
        var policies: [String: Data] = [:]
        /// Names that exist only on the server, for example ones made in the RustFS console.
        var foreignNames: Set<String> = []
        /// Bucket lists that fail with 503 before the service answers.
        var unavailableLists = 0
        var consoleStatus = 200
        /// One-time failure status for a request key such as "PUT /bucket?policy=".
        var failures: [String: Int] = [:]
        /// Changes a policy before it is saved, as a server that normalizes policies does.
        var normalize: (@Sendable (Data) -> Data)?
        /// The status of `DELETE ?policy=` on a bucket without a policy.
        var deleteWithoutPolicyStatus = 204
        var requests: [URLRequest] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func update(_ change: @Sendable (inout State) -> Void) { state.withLock { change(&$0) } }

    var current: State { state.withLock { $0 } }

    /// The request keys, for example "PUT /bucket", in order.
    var keys: [String] { current.requests.map(Self.key) }

    func send(_ request: URLRequest) async throws -> S3Response {
        state.withLock { state in
            state.requests.append(request)
            if let status = state.failures.removeValue(forKey: Self.key(request)) { return S3Response(status: status) }
            if request.url?.path == "/rustfs/console" || request.url?.path == "/rustfs/console/" {
                return S3Response(status: state.consoleStatus)
            }
            guard request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("AWS4-HMAC-SHA256 ") == true else {
                return S3Response(status: 403)
            }
            return Self.answer(request, &state)
        }
    }

    static func key(_ request: URLRequest) -> String {
        let query = request.url?.query.map { "?\($0)" } ?? ""
        return "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")\(query)"
    }

    private static func answer(_ request: URLRequest, _ state: inout State) -> S3Response {
        let name = String((request.url?.path ?? "/").dropFirst())
        let policy = request.url?.query == "policy="
        switch (request.httpMethod ?? "GET", name.isEmpty, policy) {
        case ("GET", true, _): return list(&state)
        case ("HEAD", false, _): return S3Response(status: state.buckets.contains(name) ? 200 : 404)
        case ("PUT", false, false):
            state.buckets.insert(name)
            return S3Response(status: 200)
        case ("PUT", false, true):
            let body = request.httpBody ?? Data()
            state.policies[name] = state.normalize?(body) ?? body
            return S3Response(status: 204)
        case ("DELETE", false, true):
            let existed = state.policies.removeValue(forKey: name) != nil
            return S3Response(status: existed ? 204 : state.deleteWithoutPolicyStatus)
        case ("GET", false, true):
            guard let saved = state.policies[name] else { return S3Response(status: 404) }
            return S3Response(status: 200, body: saved)
        default: return S3Response(status: 400)
        }
    }

    private static func list(_ state: inout State) -> S3Response {
        if state.unavailableLists > 0 {
            state.unavailableLists -= 1
            return S3Response(status: 503)
        }
        let names = (state.buckets.union(state.foreignNames)).sorted()
        let items = names.map { "<Bucket><Name>\($0)</Name></Bucket>" }.joined()
        let xml =
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?><ListAllMyBucketsResult "
            + "xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\"><Buckets>\(items)</Buckets></ListAllMyBucketsResult>"
        return S3Response(status: 200, body: Data(xml.utf8))
    }
}
