import Foundation
import CryptoKit

/// A small path-style S3 client for Jerd's owned loopback service.
/// Credentials remain in memory and never appear in process arguments or URLs.
public struct StorageS3Client: Sendable {
    private let port: UInt16
    private let region: String
    private let credentials: StorageCredentials
    private let session: URLSession

    public init(port: UInt16, region: String = "us-east-1", credentials: StorageCredentials) {
        self.port = port; self.region = region; self.credentials = credentials
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = ["HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0]
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 8
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: NoStorageRedirects(), delegateQueue: nil)
    }
    public func close() { session.invalidateAndCancel() }

    public func listBuckets() async throws -> Set<String> {
        let response = try await request("GET")
        try check(response)
        return try S3XML.names(in: response.data)
    }

    public func bucketExists(_ name: String) async throws -> Bool {
        try StorageBucket.validateName(name)
        let response = try await request("HEAD", path: "/" + name)
        if response.status == 404 { return false }
        try check(response)
        return true
    }

    public func createBucket(_ name: String) async throws {
        try StorageBucket.validateName(name)
        try check(await request("PUT", path: "/" + name))
    }

    public func configureAccess(_ bucket: StorageBucket) async throws {
        try StorageBucket.validateName(bucket.name)
        let response: Response
        if bucket.publicRead {
            response = try await request("PUT", path: "/" + bucket.name, query: ["policy": ""], body: Self.readPolicy(bucket.name))
        } else {
            response = try await request("DELETE", path: "/" + bucket.name, query: ["policy": ""])
        }
        try check(response)
        guard try await isPublicRead(bucket.name) == bucket.publicRead else {
            throw JerdError.process("The bucket access settings could not be verified. Retry setup.")
        }
    }

    public func isPublicRead(_ name: String) async throws -> Bool {
        let response = try await request("GET", path: "/" + name, query: ["policy": ""])
        if response.status == 404 { return false }
        try check(response)
        let actual = try JSONSerialization.jsonObject(with: response.data) as? NSDictionary
        let expected = try JSONSerialization.jsonObject(with: Self.readPolicy(name)) as? NSDictionary
        guard actual == expected else {
            throw JerdError.invalid("Bucket \(name) has a custom access policy. Use the RustFS console to inspect it.")
        }
        return true
    }

    private static func readPolicy(_ name: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "Version": "2012-10-17",
            "Statement": [["Effect": "Allow", "Principal": ["AWS": ["*"]],
                           "Action": ["s3:GetObject"], "Resource": ["arn:aws:s3:::\(name)/*"]]]
        ], options: [.sortedKeys])
    }

    struct Response: Sendable { let status: Int; let data: Data }

    func request(_ method: String, path: String = "/", query: [String: String] = [:], body: Data = Data(),
                 authenticated: Bool = true) async throws -> Response {
        var components = URLComponents()
        components.scheme = "http"; components.host = "127.0.0.1"; components.port = Int(port)
        components.percentEncodedPath = Self.encode(path, preserveSlash: true)
        let encodedPairs: [(String, String)] = query.map { (Self.encode($0.key), Self.encode($0.value)) }
        let sortedPairs = encodedPairs.sorted { left, right in
            left.0 == right.0 ? left.1 < right.1 : left.0 < right.0
        }
        let encodedQuery = sortedPairs.map { $0.0 + "=" + $0.1 }.joined(separator: "&")
        if !encodedQuery.isEmpty { components.percentEncodedQuery = encodedQuery }
        guard let url = components.url, path.hasPrefix("/") else { throw JerdError.invalid("Invalid local S3 path.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if !body.isEmpty { request.httpBody = body }
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        if authenticated {
            Self.sign(&request, body: body, canonicalPath: components.percentEncodedPath, canonicalQuery: encodedQuery,
                      region: region, credentials: credentials, date: Date())
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JerdError.process("RustFS returned an invalid response.") }
        let limit: Int64 = 4 * 1024 * 1024
        guard (response.expectedContentLength < 0 || response.expectedContentLength <= limit),
              Int64(data.count) <= limit else { throw JerdError.process("The RustFS response exceeds the size limit.") }
        return Response(status: http.statusCode, data: data)
    }

    private func check(_ response: Response) throws {
        guard (200..<300).contains(response.status) else {
            // Server response bodies can contain signed request details. Do not display them.
            throw JerdError.process("RustFS returned HTTP \(response.status). Check the storage log and retry.")
        }
    }

    static func encode(_ value: String, preserveSlash: Bool = false) -> String {
        value.utf8.map { byte in
            if (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) ||
                [45, 46, 95, 126].contains(byte) || (preserveSlash && byte == 47) {
                return String(UnicodeScalar(byte))
            }
            return String(format: "%%%02X", byte)
        }.joined()
    }

    static func sign(_ request: inout URLRequest, body: Data, canonicalPath: String, canonicalQuery: String,
                     region: String, credentials: StorageCredentials, date: Date) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let timestamp = formatter.string(from: date)
        let day = String(timestamp.prefix(8))
        let host = request.url!.host! + (request.url!.port.map { ":\($0)" } ?? "")
        let payloadHash = hash(body)
        let headers = "host:\(host)\nx-amz-content-sha256:\(payloadHash)\nx-amz-date:\(timestamp)\n"
        let signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        let canonical = [request.httpMethod!, canonicalPath, canonicalQuery, headers, signedHeaders, payloadHash].joined(separator: "\n")
        let scope = "\(day)/\(region)/s3/aws4_request"
        let signingText = "AWS4-HMAC-SHA256\n\(timestamp)\n\(scope)\n\(hash(Data(canonical.utf8)))"
        var key = hmac(Data(("AWS4" + credentials.secretKey).utf8), day)
        for component in [region, "s3", "aws4_request"] { key = hmac(key, component) }
        let signature = hmac(key, signingText).map { String(format: "%02x", $0) }.joined()
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(timestamp, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue("AWS4-HMAC-SHA256 Credential=\(credentials.accessKey)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)",
                         forHTTPHeaderField: "Authorization")
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func hmac(_ key: Data, _ value: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: key)))
    }
}

private final class NoStorageRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class S3XML: NSObject, XMLParserDelegate {
    private var path: [String] = []
    private var current = ""
    private var buckets: Set<String> = []
    private var validRoot = false
    static func names(in data: Data) throws -> Set<String> {
        let delegate = S3XML()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.validRoot else { throw JerdError.process("RustFS returned an invalid bucket list.") }
        for name in delegate.buckets { try StorageBucket.validateName(name) }
        return delegate.buckets
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        path.append(elementName); current = ""
        if path == ["ListAllMyBucketsResult"] { validRoot = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { current += string }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if path == ["ListAllMyBucketsResult", "Buckets", "Bucket", "Name"] { buckets.insert(current) }
        path.removeLast(); current = ""
    }
}
