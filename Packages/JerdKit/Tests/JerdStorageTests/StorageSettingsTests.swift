import Foundation
import JerdFoundation
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdStorage

@Suite struct StorageSettingsTests {
    static let runtime = StorageRuntime(
        id: "rustfs-1.0.0-arm64", version: "1.0.0",
        path: "/Users/me/Library/Application Support/Jerd/storage-runtimes/rustfs-1.0.0-arm64")
    static let credentials = S3ClientTests.credentials

    @Test func settingsOfOlderBuildsDecodeAndEncodeToTheSameBytes() throws {
        let bytes = try golden("storage-settings.json")
        let settings = try JSONDecoder().decode(StorageSettings.self, from: bytes)
        try settings.validate()
        let buckets = [
            StorageBucket(name: "app-uploads", publicRead: false, setupComplete: true),
            StorageBucket(name: "public.assets", publicRead: true, setupComplete: false),
        ]
        #expect(
            settings
                == StorageSettings(
                    runtime: Self.runtime, ports: StoragePorts(api: 9_002, console: 9_003), buckets: buckets))
        #expect(try JSONFileFormat.settings.makeEncoder().encode(settings) == bytes)
        #expect(try JSONDecoder().decode(StorageRuntime.self, from: golden("storage-runtime.json")) == Self.runtime)
    }

    @Test(arguments: ["schemaVersion", "apiPort", "consolePort", "buckets"])
    func everyRequiredSettingsKeyIsRequired(_ key: String) throws {
        let object = try jsonObject(try golden("storage-settings.json")).mutableCopy() as! NSMutableDictionary
        object.removeObject(forKey: key)
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(StorageSettings.self, from: data) }
    }

    @Test(arguments: ["name", "publicRead", "setupComplete"])
    func everyBucketKeyIsRequiredAndTheIDIsNotSaved(_ key: String) throws {
        let bucket = StorageBucket(name: "app-uploads")
        let encoded =
            try jsonObject(JSONFileFormat.settings.makeEncoder().encode(bucket)).mutableCopy() as! NSMutableDictionary
        #expect(encoded["id"] == nil)
        encoded.removeObject(forKey: key)
        let data = try JSONSerialization.data(withJSONObject: encoded)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(StorageBucket.self, from: data) }
    }

    @Test(arguments: [
        "UPPERCASE", "ab", "-uploads", "uploads-", "a..b", "a.-b", "a-.b", "127.0.0.1", "xn--bucket", "sthree-x",
        "amzn-s3-demo-x", "demo-s3alias", "demo--ol-s3", "demo.mrap", "demo--x-s3", "demo--table-s3", "a/b",
        "hello\nworld", "café", String(repeating: "a", count: 64),
    ])
    func invalidBucketNamesAreRejected(_ name: String) {
        #expect(throws: StorageMessages.bucketNameInvalid) { try BucketName.validate(name) }
    }

    @Test(arguments: ["abc", "my-app.uploads", "1.2.3", String(repeating: "a", count: 63), "0bucket9"])
    func validBucketNamesAreAccepted(_ name: String) throws {
        try BucketName.validate(name)
    }

    @Test func settingsRulesRejectBadPortsDuplicatesAndRuntimes() {
        let bucket = StorageBucket(name: "app-uploads")
        for settings in [
            StorageSettings(ports: StoragePorts(api: 9_000, console: 9_000)),
            StorageSettings(ports: StoragePorts(api: 80, console: 9_001)),
            StorageSettings(buckets: [bucket, bucket]),
            StorageSettings(buckets: Array(repeating: bucket, count: 1_001)),
        ] {
            #expect(throws: StorageMessages.settingsInvalid) { try settings.validate() }
        }
        #expect(throws: StorageMessages.bucketNameInvalid) {
            try StorageSettings(buckets: [StorageBucket(name: "Bad")]).validate()
        }
        #expect(throws: StorageMessages.runtimeRecordInvalid) {
            try StorageSettings(runtime: StorageRuntime(id: "rustfs", version: "1.0.0", path: "relative")).validate()
        }
    }

    @Test func laravelEnvironmentUsesThePathStyleLocalEndpoint() {
        let settings = StorageSettings(ports: StoragePorts(api: 19_123, console: 19_124))
        let text = settings.laravelEnvironment(
            bucket: StorageBucket(name: "app-uploads"), credentials: Self.credentials)
        #expect(
            text
                == "FILESYSTEM_DISK=s3\nAWS_ACCESS_KEY_ID=JERD0123456789ABCDEF\n"
                + "AWS_SECRET_ACCESS_KEY=00112233445566778899AABBCCDDEEFF0011223344556677\n"
                + "AWS_DEFAULT_REGION=us-east-1\nAWS_BUCKET=app-uploads\nAWS_ENDPOINT=http://127.0.0.1:19123\n"
                + "AWS_URL=http://127.0.0.1:19123/app-uploads\nAWS_USE_PATH_STYLE_ENDPOINT=true\n")
        #expect(settings.consoleURL.absoluteString == "http://127.0.0.1:19124/rustfs/console/")
    }

    @Test func credentialsHaveTheirFixedFormsAndAreUnique() throws {
        let first = try StorageCredentials.generate()
        try first.validate()
        #expect(first.accessKey.hasPrefix("JERD") && first.accessKey.count == 20)
        #expect(HexEncoding.isHex(String(first.accessKey.dropFirst(4)), length: 16, letterCase: .upper))
        #expect(HexEncoding.isHex(first.secretKey, length: 48, letterCase: .upper))
        #expect(try StorageCredentials.generate() != first)
        for bad in [
            StorageCredentials(accessKey: "jerd0123456789abcdef", secretKey: Self.credentials.secretKey),
            StorageCredentials(accessKey: "JERD0123", secretKey: Self.credentials.secretKey),
            StorageCredentials(accessKey: Self.credentials.accessKey, secretKey: String(repeating: "G", count: 48)),
        ] {
            #expect(throws: StorageMessages.credentialsInvalid) { try bad.validate() }
        }
    }

    @Test func aFailingRandomSourceGivesNoCredentials() {
        let failing = SecretGenerator { _ in false }
        #expect(throws: StorageMessages.credentialsUnavailable) { try StorageCredentials.generate(using: failing) }
    }

    @Test func theMarkersOfOlderBuildsDecode() throws {
        let credentials = try golden("storage-credentials.json")
        #expect(try JSONDecoder().decode(StorageCredentials.self, from: credentials) == Self.credentials)
        let marker = try JSONDecoder().decode(StorageInitializedMarker.self, from: golden("storage-initialized.json"))
        #expect(marker.runtime == Self.runtime)
        #expect(marker.credentialsHash == FileDigest.hexSHA256(of: credentials))
        #expect(marker.formatHash == FileDigest.hexSHA256(of: try golden("storage-format.json")))
    }

    @Test func aBucketStatusFollowsTheIntentTheStateAndTheList() {
        let complete = StorageBucket(name: "app", setupComplete: true)
        #expect(
            BucketStatus(bucket: StorageBucket(name: "app"), state: .running(pid: 1), listed: ["app"])
                == .setupIncomplete)
        #expect(BucketStatus(bucket: complete, state: .running(pid: 1), listed: ["app"]).title == "Ready")
        #expect(BucketStatus(bucket: complete, state: .running(pid: 1), listed: []).title == "Bucket missing")
        #expect(BucketStatus(bucket: complete, state: .stopped, listed: ["app"]).title == "Storage stopped")
        #expect(BucketStatus(bucket: complete, state: .starting, listed: []).title == "Storage starting")
        #expect(BucketStatus(bucket: complete, state: .stopping(pid: 1), listed: []).title == "Storage stopping")
        #expect(BucketStatus(bucket: complete, state: .failed(reason: "x"), listed: []).title == "Storage failed")
        let snapshot = StorageSnapshot(settings: StorageSettings(), state: .stopped, availableBuckets: ["app"])
        #expect(snapshot.availableBuckets.isEmpty)
    }

    @Test func aSaveOfABucketDecidesItsIntent() throws {
        let settings = StorageSettings(buckets: [
            StorageBucket(name: "done", setupComplete: true), StorageBucket(name: "open", publicRead: false),
        ])
        #expect(
            try BucketIntent.of(name: "fresh", publicRead: true, in: settings)
                == .new(StorageBucket(name: "fresh", publicRead: true)))
        #expect(
            try BucketIntent.of(name: "open", publicRead: false, in: settings) == .resume(StorageBucket(name: "open")))
        #expect(
            try BucketIntent.of(name: "open", publicRead: true, in: settings)
                == .change(StorageBucket(name: "open", publicRead: true)))
        #expect(throws: StorageMessages.alreadyRegistered("done")) {
            try BucketIntent.of(name: "done", publicRead: false, in: settings)
        }
        #expect(throws: StorageMessages.bucketNameInvalid) {
            try BucketIntent.of(name: "Bad", publicRead: false, in: settings)
        }
    }
}
