import Foundation
import JerdServiceKitTestSupport
import Testing

@testable import JerdStorage

/// The published AWS Signature Version 4 examples: the general test suite (`get-vanilla`,
/// `get-vanilla-query-order-key-case`) and the Amazon S3 examples of the S3 API reference.
@Suite struct S3SignerTests {
    static let emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    static let suite = S3Signer(
        accessKey: "AKIDEXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY", service: "service")
    static let s3 = S3Signer(
        accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
    static let s3Host = "examplebucket.s3.amazonaws.com"

    @Test func theVanillaGetOfTheTestSuiteMatches() {
        let request = S3Signer.Request(
            method: "GET", path: "/", query: "",
            headers: ["Host": "example.amazonaws.com", "X-Amz-Date": "20150830T123600Z"], payloadHash: Self.emptyHash)
        let signature = Self.suite.sign(request, timestamp: "20150830T123600Z")
        #expect(
            signature.canonicalRequest
                == "GET\n/\n\nhost:example.amazonaws.com\nx-amz-date:20150830T123600Z\n\nhost;x-amz-date\n"
                + Self.emptyHash)
        #expect(signature.signature == "5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31")
        #expect(
            signature.authorization
                == "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/service/aws4_request, "
                + "SignedHeaders=host;x-amz-date, "
                + "Signature=5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31")
    }

    @Test func theQueryOrderExampleOfTheTestSuiteMatches() {
        let query = S3URIEncoding.canonicalQuery(["Param2": "value2", "Param1": "value1"])
        #expect(query == "Param1=value1&Param2=value2")
        let request = S3Signer.Request(
            method: "GET", path: "/", query: query,
            headers: ["host": "example.amazonaws.com", "x-amz-date": "20150830T123600Z"], payloadHash: Self.emptyHash)
        #expect(
            Self.suite.sign(request, timestamp: "20150830T123600Z").signature
                == "b97d918cfa904a5beff61c982a1b6f458b799221646efd99d3219ec94cdf2500")
    }

    @Test func theS3GetObjectExampleMatches() {
        let request = S3Signer.Request(
            method: "GET", path: "/test.txt", query: "",
            headers: [
                "Host": Self.s3Host, "Range": "bytes=0-9", "x-amz-content-sha256": Self.emptyHash,
                "x-amz-date": "20130524T000000Z",
            ], payloadHash: Self.emptyHash)
        #expect(
            Self.s3.sign(request, timestamp: "20130524T000000Z").signature
                == "f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41")
    }

    @Test func theS3PutObjectExampleMatches() {
        let body = Data("Welcome to Amazon S3.".utf8)
        let hash = S3Signer.payloadHash(body)
        #expect(hash == "44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072")
        let request = S3Signer.Request(
            method: "PUT", path: S3URIEncoding.encode("/test$file.text", keepingSlash: true), query: "",
            headers: [
                "Date": "Fri, 24 May 2013 00:00:00 GMT", "Host": Self.s3Host, "x-amz-content-sha256": hash,
                "x-amz-date": "20130524T000000Z", "x-amz-storage-class": "REDUCED_REDUNDANCY",
            ], payloadHash: hash)
        #expect(
            Self.s3.sign(request, timestamp: "20130524T000000Z").signature
                == "98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd")
    }

    @Test(arguments: [
        (["lifecycle": ""], "fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543"),
        (["max-keys": "2", "prefix": "J"], "34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7"),
    ])
    func theS3BucketExamplesWithJerdsSignedHeadersMatch(_ query: [String: String], _ expected: String) {
        let request = S3Signer.Request(
            method: "GET", path: "/", query: S3URIEncoding.canonicalQuery(query),
            headers: ["host": Self.s3Host, "x-amz-content-sha256": Self.emptyHash, "x-amz-date": "20130524T000000Z"],
            payloadHash: Self.emptyHash)
        let signature = Self.s3.sign(request, timestamp: "20130524T000000Z")
        #expect(signature.signature == expected)
        #expect(signature.authorization.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date,"))
        #expect(signature.authorization.contains("Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request"))
    }

    @Test func theTimestampIsUTCAndTheEmptyPayloadHashIsKnown() {
        #expect(S3Signer.timestamp(for: Date(timeIntervalSince1970: 1_369_353_600)) == "20130524T000000Z")
        #expect(S3Signer.timestamp(for: Date(timeIntervalSince1970: 1_440_938_160)) == "20150830T123600Z")
        #expect(S3Signer.payloadHash(Data()) == Self.emptyHash)
    }

    @Test func pathsAndQueriesAreEncodedByteByByte() {
        #expect(S3URIEncoding.encode("/bucket/café +%?.txt", keepingSlash: true) == "/bucket/caf%C3%A9%20%2B%25%3F.txt")
        #expect(S3URIEncoding.encode("a/b~c_d-e.f") == "a%2Fb~c_d-e.f")
        #expect(S3URIEncoding.canonicalQuery(["policy": ""]) == "policy=")
        #expect(S3URIEncoding.canonicalQuery(["b": "2", "a": "x y"]) == "a=x%20y&b=2")
        #expect(S3URIEncoding.canonicalQuery([:]) == "")
    }

    /// A log line, `dump`, or a test failure of credentials, a signer, or a client never shows
    /// the secret key.
    @Test func printedCredentialsSignersAndClientsNeverShowTheSecretKey() {
        let credentials = S3ClientTests.credentials
        let client = S3Client(port: 19_123, credentials: credentials, sender: FakeS3Server())
        var dumped = ""
        dump(credentials, to: &dumped)
        dump(client, to: &dumped)
        let texts = [
            String(describing: credentials), String(reflecting: credentials), "\(client.signer)",
            String(reflecting: client.signer), String(describing: client), String(reflecting: client), dumped,
        ]
        for text in texts { #expect(!text.contains(credentials.secretKey), "\(text.count) characters") }
        #expect(String(describing: credentials).contains(credentials.accessKey))
        #expect(dumped.contains("[redacted]"))
    }
}
