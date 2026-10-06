import CryptoKit
import Foundation
import JerdFoundation

/// AWS Signature Version 4 (`AWS4-HMAC-SHA256`). Pure: the time is an input, and nothing is sent.
///
/// The signed headers are every header of the request, by lowercase name. Jerd signs `host`,
/// `x-amz-content-sha256`, and `x-amz-date`.
public struct S3Signer: Sendable {
    /// The parts of one request that the signature covers.
    public struct Request: Equatable, Sendable {
        public var method: String
        /// The URI-encoded path, for example `/bucket/caf%C3%A9.txt`.
        public var path: String
        /// The canonical query, for example `policy=`.
        public var query: String
        /// The headers to sign. Names are compared without case.
        public var headers: [String: String]
        /// The lowercase hexadecimal SHA-256 of the body.
        public var payloadHash: String

        public init(method: String, path: String, query: String, headers: [String: String], payloadHash: String) {
            self.method = method
            self.path = path
            self.query = query
            self.headers = headers
            self.payloadHash = payloadHash
        }
    }

    /// Every intermediate result, so tests can compare each step with the AWS examples.
    public struct Signature: Equatable, Sendable {
        public let canonicalRequest: String
        public let stringToSign: String
        /// The lowercase hexadecimal signature.
        public let signature: String
        /// The value of the `Authorization` header.
        public let authorization: String
    }

    public let accessKey: String
    let secretKey: String
    public let region: String
    public let service: String

    public init(accessKey: String, secretKey: String, region: String = "us-east-1", service: String = "s3") {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
        self.service = service
    }

    /// Signs `request` at `timestamp` (`yyyyMMdd'T'HHmmss'Z'`, UTC).
    public func sign(_ request: Request, timestamp: String) -> Signature {
        let headers = request.headers.map { (Self.lowercase($0.key), Self.trim($0.value)) }.sorted { $0.0 < $1.0 }
        let canonicalHeaders = headers.map { "\($0.0):\($0.1)\n" }.joined()
        let signedHeaders = headers.map(\.0).joined(separator: ";")
        let canonical = [
            request.method, request.path, request.query, canonicalHeaders, signedHeaders, request.payloadHash,
        ].joined(separator: "\n")
        let day = String(timestamp.prefix(8))
        let scope = "\(day)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256", timestamp, scope, FileDigest.hexSHA256(of: Data(canonical.utf8)),
        ].joined(separator: "\n")
        var key = Self.hmac(Data("AWS4\(secretKey)".utf8), day)
        for part in [region, service, "aws4_request"] { key = Self.hmac(key, part) }
        let signature = HexEncoding.string(Self.hmac(key, stringToSign))
        let authorization =
            "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        return Signature(
            canonicalRequest: canonical, stringToSign: stringToSign, signature: signature,
            authorization: authorization)
    }

    /// `yyyyMMdd'T'HHmmss'Z'` in UTC, from the Gregorian calendar.
    public static func timestamp(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0,
            parts.minute ?? 0, parts.second ?? 0)
    }

    /// The lowercase hexadecimal SHA-256 of `body`.
    public static func payloadHash(_ body: Data) -> String { FileDigest.hexSHA256(of: body) }

    private static func hmac(_ key: Data, _ text: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: key)))
    }

    private static func lowercase(_ name: String) -> String { name.lowercased() }

    /// Removes outer white space and folds inner runs of spaces to one, as SigV4 requires.
    private static func trim(_ value: String) -> String {
        value.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
