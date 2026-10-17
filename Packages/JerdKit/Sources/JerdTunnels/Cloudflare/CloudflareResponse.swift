import Foundation
import JerdFoundation

/// The envelope of every Cloudflare API answer: `success`, `errors`, `result`, and for lists
/// `result_info`.
struct CloudflareResponse<Result: Decodable>: Decodable {
    struct Failure: Decodable {
        let code: Int
        let message: String
    }

    struct Pages: Decodable {
        let totalPages: Int?

        enum CodingKeys: String, CodingKey { case totalPages = "total_pages" }
    }

    let success: Bool
    let errors: [Failure]?
    let result: Result?
    let resultInfo: Pages?

    enum CodingKeys: String, CodingKey {
        case success, errors, result
        case resultInfo = "result_info"
    }

    /// 401 means the token is invalid. 403 and code 10000 mean that it lacks a permission, but
    /// Cloudflare's message does not name it, so Jerd lists the permissions.
    static func decode(status: Int, body: Data) throws -> CloudflareResponse<Result> {
        if status == 401 { throw JerdError.invalid(CloudflareMessage.tokenRejected) }
        guard let response = try? JSONDecoder().decode(Self.self, from: body) else {
            if status == 403 { throw JerdError.invalid(CloudflareMessage.missingPermission("HTTP 403")) }
            throw JerdError.unavailable(CloudflareMessage.invalidResponse)
        }
        guard response.success, (200..<300).contains(status) else {
            let errors = response.errors ?? []
            let detail = errors.map { "\($0.message) (\($0.code))" }.joined(separator: "; ")
            let shown = detail.isEmpty ? "HTTP \(status)" : detail
            if status == 403 || errors.contains(where: { $0.code == Self.authenticationError }) {
                throw JerdError.invalid(CloudflareMessage.missingPermission(shown))
            }
            throw JerdError.unavailable(CloudflareMessage.failed(shown))
        }
        return response
    }

    /// Cloudflare's code for a token that may not make this request.
    static var authenticationError: Int { 10000 }

    /// The result of a successful answer that must have one.
    func requireResult() throws -> Result {
        guard let result else { throw JerdError.unavailable(CloudflareMessage.invalidResponse) }
        return result
    }
}

/// A result whose content Jerd does not read, for example of a DELETE.
struct CloudflareIgnoredResult: Decodable {
    init(from decoder: any Decoder) throws {}
}
