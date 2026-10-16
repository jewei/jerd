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

    /// 401 means the token is invalid. Any other refusal shows Cloudflare's own messages, which
    /// name the missing permission.
    static func decode(status: Int, body: Data) throws -> CloudflareResponse<Result> {
        if status == 401 { throw JerdError.invalid(CloudflareMessage.tokenRejected) }
        guard let response = try? JSONDecoder().decode(Self.self, from: body) else {
            throw JerdError.unavailable(CloudflareMessage.invalidResponse)
        }
        guard response.success, (200..<300).contains(status) else {
            let detail = (response.errors ?? []).map { "\($0.message) (\($0.code))" }.joined(separator: "; ")
            throw JerdError.unavailable(CloudflareMessage.failed(detail.isEmpty ? "HTTP \(status)" : detail))
        }
        return response
    }

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
