import Foundation
import JerdFoundation
import JerdServiceKitTestSupport
import Testing

@testable import JerdStorage

@Suite struct S3ParsingAndPolicyTests {
    static func list(_ names: [String], root: String = "ListAllMyBucketsResult", prefix: String = "") -> Data {
        let items = names.map { "<\(prefix)Bucket><\(prefix)Name>\($0)</\(prefix)Name></\(prefix)Bucket>" }.joined()
        let namespace = prefix.isEmpty ? "xmlns" : "xmlns:\(prefix.dropLast())"
        return Data(
            ("<?xml version=\"1.0\"?><\(prefix)\(root) \(namespace)=\"http://s3.amazonaws.com/doc/2006-03-01/\">"
                + "<\(prefix)Buckets>\(items)</\(prefix)Buckets><\(prefix)Owner><\(prefix)ID>x</\(prefix)ID>"
                + "</\(prefix)Owner></\(prefix)\(root)>").utf8)
    }

    @Test func aBucketListGivesItsNamesWithOrWithoutANamespacePrefix() throws {
        #expect(
            try S3XMLParsers.bucketNames(in: Self.list(["app-uploads", "public.assets"])) == [
                "app-uploads", "public.assets",
            ])
        #expect(try S3XMLParsers.bucketNames(in: Self.list(["app-uploads"], prefix: "s3:")) == ["app-uploads"])
        #expect(try S3XMLParsers.bucketNames(in: Self.list([])).isEmpty)
    }

    @Test func serverNamesThatBreakJerdsRulesAreLeftOutNotAnError() throws {
        let names = try S3XMLParsers.bucketNames(in: Self.list(["app-uploads", "demo--x-s3", "UPPER", "xn--bucket"]))
        #expect(names == ["app-uploads"])
    }

    @Test(arguments: [
        Data("not xml".utf8), Data(), list(["app"], root: "Error"),
        Data("<ListAllMyBucketsResult><Buckets><Bucket>".utf8),
    ])
    func anythingElseIsAnInvalidBucketList(_ data: Data) {
        #expect(throws: StorageMessages.invalidBucketList) { try S3XMLParsers.bucketNames(in: data) }
    }

    @Test func externalEntitiesAreNeverResolved() throws {
        let secret = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-entity-\(UUID().uuidString)")
        try Data("leaked-bucket".utf8).write(to: secret)
        defer { try? FileManager.default.removeItem(at: secret) }
        let xml =
            "<?xml version=\"1.0\"?><!DOCTYPE r [<!ENTITY x SYSTEM \"\(secret.absoluteString)\">]>"
            + "<ListAllMyBucketsResult><Buckets><Bucket><Name>&x;</Name></Bucket></Buckets></ListAllMyBucketsResult>"
        let names = (try? S3XMLParsers.bucketNames(in: Data(xml.utf8))) ?? []
        #expect(!names.contains("leaked-bucket"))
    }

    @Test func thePublicPolicyHasTheExactBytesOfOlderBuilds() throws {
        let object: [String: Any] = [
            "Version": "2012-10-17",
            "Statement": [
                [
                    "Effect": "Allow", "Principal": ["AWS": ["*"]], "Action": ["s3:GetObject"],
                    "Resource": ["arn:aws:s3:::public.assets/*"],
                ]
            ],
        ]
        let old = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(BucketPolicy.publicReadDocument(bucket: "public.assets") == old)
        #expect(try BucketPolicy.access(of: old, bucket: "public.assets") == .publicRead)
    }

    @Test(arguments: [
        #"{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::app/*"}]}"#,
        #"{"Version":"2012-10-17","Statement":{"Sid":"read","Effect":"Allow","Principal":{"AWS":"*"},"Action":["s3:GetObject"],"Resource":["arn:aws:s3:::app/*"]}}"#,
        #"{"Id":"jerd","Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":["*"]},"Action":["s3:GetObject"],"Resource":"arn:aws:s3:::app/*"}]}"#,
    ])
    func equivalentPublicReadFormsAreAccepted(_ text: String) throws {
        #expect(try BucketPolicy.access(of: Data(text.utf8), bucket: "app") == .publicRead)
    }

    @Test func noPolicyOrNoStatementIsPrivate() throws {
        #expect(try BucketPolicy.access(of: nil, bucket: "app") == .privateOnly)
        let empty = Data(#"{"Version":"2012-10-17","Statement":[]}"#.utf8)
        #expect(try BucketPolicy.access(of: empty, bucket: "app") == .privateOnly)
    }

    @Test(arguments: [
        #"{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*","Action":["s3:GetObject","s3:PutObject"],"Resource":"arn:aws:s3:::app/*"}]}"#,
        #"{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*","Action":"s3:ListBucket","Resource":"arn:aws:s3:::app"}]}"#,
        #"{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::other/*"}]}"#,
        #"{"Version":"2012-10-17","Statement":[{"Effect":"Deny","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::app/*"}]}"#,
        #"{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":["arn:aws:iam::1:root"]},"Action":"s3:GetObject","Resource":"arn:aws:s3:::app/*"}]}"#,
        #"{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::app/*","Condition":{}}]}"#,
        #"{"Version":"2008-10-17","Statement":[]}"#, #"not json"#,
    ])
    func anyOtherPolicyIsACustomPolicy(_ text: String) {
        #expect(throws: StorageMessages.customPolicy("app")) {
            try BucketPolicy.access(of: Data(text.utf8), bucket: "app")
        }
    }
}
