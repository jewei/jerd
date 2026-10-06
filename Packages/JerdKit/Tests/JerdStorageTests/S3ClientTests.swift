import Foundation
import JerdFoundation
import Testing

@testable import JerdStorage

@Suite struct S3ClientTests {
    static let credentials = StorageCredentials(
        accessKey: "JERD0123456789ABCDEF", secretKey: "00112233445566778899AABBCCDDEEFF0011223344556677")
    static let date = Date(timeIntervalSince1970: 1_369_353_600)

    static func client(_ server: FakeS3Server = FakeS3Server()) -> S3Client {
        S3Client(port: 19_123, credentials: credentials, sender: server, now: { Self.date })
    }

    @Test func aSignedRequestHasTheSigV4HeadersAndNoSecret() throws {
        let body = Data("payload".utf8)
        let request = try Self.client().makeRequest(
            "PUT", path: "/bucket/café +%?.txt", query: ["policy": ""], body: body, signed: true)
        #expect(request.url?.absoluteString == "http://127.0.0.1:19123/bucket/caf%C3%A9%20%2B%25%3F.txt?policy=")
        #expect(request.httpBody == body)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(request.value(forHTTPHeaderField: "x-amz-date") == "20130524T000000Z")
        #expect(request.value(forHTTPHeaderField: "x-amz-content-sha256") == S3Signer.payloadHash(body))
        let authorization = try #require(request.value(forHTTPHeaderField: "Authorization"))
        #expect(authorization.hasPrefix("AWS4-HMAC-SHA256 Credential=JERD0123456789ABCDEF/20130524/us-east-1/s3/"))
        #expect(authorization.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date"))
        #expect(!authorization.contains(Self.credentials.secretKey))
        #expect(!(request.url?.absoluteString.contains(Self.credentials.accessKey) ?? true))
    }

    @Test func anAnonymousRequestHasNoSignatureAndAnEmptyBodyIsNotSent() throws {
        let request = try Self.client().makeRequest("GET", path: "/", query: [:], body: Data(), signed: false)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.httpBody == nil)
        #expect(request.url?.absoluteString == "http://127.0.0.1:19123/")
    }

    @Test func aPathMustStartWithASlashAndBucketNamesCannotChangeThePath() async throws {
        #expect(throws: StorageMessages.invalidPath) {
            try Self.client().makeRequest("GET", path: "bucket", query: [:], body: Data(), signed: true)
        }
        await #expect(throws: StorageMessages.bucketNameInvalid) { try await Self.client().createBucket("a/../b") }
    }

    @Test func bucketOperationsUseTheirExactRequests() async throws {
        let server = FakeS3Server()
        let client = Self.client(server)
        #expect(try await !client.bucketExists("app-uploads"))
        try await client.createBucket("app-uploads")
        #expect(try await client.bucketExists("app-uploads"))
        #expect(try await client.policy(of: "app-uploads") == nil)
        try await client.deletePolicy(of: "app-uploads")
        try await client.putPolicy(Data("{}".utf8), on: "app-uploads")
        #expect(try await client.policy(of: "app-uploads") == Data("{}".utf8))
        #expect(try await client.listBuckets() == ["app-uploads"])
        #expect(
            server.keys == [
                "HEAD /app-uploads", "PUT /app-uploads", "HEAD /app-uploads", "GET /app-uploads?policy=",
                "DELETE /app-uploads?policy=", "PUT /app-uploads?policy=", "GET /app-uploads?policy=", "GET /",
            ])
    }

    @Test func aStatusOutside2xxNamesOnlyTheStatus() async throws {
        let server = FakeS3Server()
        server.update { $0.failures["PUT /app-uploads"] = 409 }
        await #expect(throws: StorageMessages.httpStatus(409)) {
            try await Self.client(server).createBucket("app-uploads")
        }
        server.update { $0.failures["HEAD /app-uploads"] = 500 }
        await #expect(throws: StorageMessages.httpStatus(500)) {
            try await Self.client(server).bucketExists("app-uploads")
        }
    }

    @Test func removingAPolicyThatDoesNotExistIsFine() async throws {
        let server = FakeS3Server()
        server.update { $0.deleteWithoutPolicyStatus = 404 }
        try await Self.client(server).deletePolicy(of: "app-uploads")
        server.update { $0.deleteWithoutPolicyStatus = 500 }
        await #expect(throws: StorageMessages.httpStatus(500)) {
            try await Self.client(server).deletePolicy(of: "app-uploads")
        }
    }
}
