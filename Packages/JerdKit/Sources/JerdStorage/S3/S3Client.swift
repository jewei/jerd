import Foundation
import JerdFoundation

/// A small path-style S3 client for Jerd's own loopback RustFS service.
///
/// Every request is signed with SigV4 unless the caller asks for an anonymous one. Bodies of
/// answers are never shown in messages, because they can echo signed request details.
struct S3Client: Sendable {
    let port: UInt16
    let signer: S3Signer
    let sender: any S3Sending
    let now: @Sendable () -> Date

    init(
        port: UInt16, credentials: StorageCredentials, sender: any S3Sending,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.port = port
        signer = S3Signer(
            accessKey: credentials.accessKey, secretKey: credentials.secretKey, region: StorageSettings.region)
        self.sender = sender
        self.now = now
    }

    /// The names of every bucket that Jerd's name rules allow.
    func listBuckets() async throws -> Set<String> {
        try S3XMLParsers.bucketNames(in: try require(await send("GET")).body)
    }

    /// `HEAD /<name>`: true for 2xx, false for 404.
    func bucketExists(_ name: String) async throws -> Bool {
        let response = try await send("HEAD", path: try Self.path(of: name))
        if response.status == 404 { return false }
        try require(response)
        return true
    }

    func createBucket(_ name: String) async throws {
        try require(await send("PUT", path: try Self.path(of: name)))
    }

    /// The saved policy document, or nil when the bucket has none.
    func policy(of name: String) async throws -> Data? {
        let response = try await send("GET", path: try Self.path(of: name), query: ["policy": ""])
        if response.status == 404 { return nil }
        return try require(response).body
    }

    func putPolicy(_ document: Data, on name: String) async throws {
        try require(await send("PUT", path: try Self.path(of: name), query: ["policy": ""], body: document))
    }

    /// Removes the policy. A bucket without a policy (404) is also fine.
    func deletePolicy(of name: String) async throws {
        let response = try await send("DELETE", path: try Self.path(of: name), query: ["policy": ""])
        if response.status != 404 { try require(response) }
    }

    /// Sends one request to `127.0.0.1:<port>`.
    func send(
        _ method: String, path: String = "/", query: [String: String] = [:], body: Data = Data(), signed: Bool = true
    ) async throws -> S3Response {
        try await sender.send(makeRequest(method, path: path, query: query, body: body, signed: signed))
    }

    /// Builds the URL request: the encoded path and query, the body, and the SigV4 headers.
    func makeRequest(
        _ method: String, path: String, query: [String: String], body: Data, signed: Bool
    ) throws -> URLRequest {
        guard path.hasPrefix("/") else { throw StorageMessages.invalidPath }
        let encodedPath = S3URIEncoding.encode(path, keepingSlash: true)
        let encodedQuery = S3URIEncoding.canonicalQuery(query)
        let host = "127.0.0.1:\(port)"
        let suffix = encodedQuery.isEmpty ? "" : "?\(encodedQuery)"
        guard let url = URL(string: "http://\(host)\(encodedPath)\(suffix)") else { throw StorageMessages.invalidPath }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if !body.isEmpty { request.httpBody = body }
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        guard signed else { return request }
        let payloadHash = S3Signer.payloadHash(body)
        let timestamp = S3Signer.timestamp(for: now())
        let headers = ["host": host, "x-amz-content-sha256": payloadHash, "x-amz-date": timestamp]
        let signature = signer.sign(
            S3Signer.Request(
                method: method, path: encodedPath, query: encodedQuery, headers: headers, payloadHash: payloadHash),
            timestamp: timestamp)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue(signature.authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    /// `/<name>` for a valid bucket name, so a name can never change the request path.
    static func path(of name: String) throws -> String {
        try BucketName.validate(name)
        return "/\(name)"
    }

    /// Requires a 2xx status. The body is never shown.
    @discardableResult
    private func require(_ response: S3Response) throws -> S3Response {
        guard response.succeeded else { throw StorageMessages.httpStatus(response.status) }
        return response
    }
}
