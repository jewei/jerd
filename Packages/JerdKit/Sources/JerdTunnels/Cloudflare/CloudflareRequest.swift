import Foundation
import JerdFoundation

/// Builds the requests of `CloudflareClient`.
enum CloudflareRequest {
    static let host = "api.cloudflare.com"

    /// Each path segment must be a fixed word, a Cloudflare ID, or a lower-case UUID, so no value
    /// can change the path.
    static func make(
        _ method: String, _ path: [String], query: [String: String], body: Data?, token: String
    ) throws
        -> URLRequest
    {
        guard path.allSatisfy(isSafeSegment) else { throw JerdError.invalid(CloudflareMessage.invalidRecord) }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/client/v4/" + path.joined(separator: "/")
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw JerdError.invalid(CloudflareMessage.invalidRecord) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private static func isSafeSegment(_ segment: String) -> Bool {
        !segment.isEmpty && segment.count <= 64
            && segment.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
    }
}
