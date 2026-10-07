import Foundation
import JerdFoundation
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdStorage

@Suite struct RustFSDefinitionTests {
    static let layout = DataLayout(root: URL(fileURLWithPath: "/Users/me/Library/Application Support/Jerd"))

    static func definition(
        server: FakeS3Server = FakeS3Server(), launch: StorageLaunch = StorageLaunch()
    )
        -> RustFSDefinition
    {
        RustFSDefinition(
            runtime: StorageSettingsTests.runtime, ports: StoragePorts(api: 9_002, console: 9_003),
            layout: layout.storage, dataRoot: layout.root, launch: launch, makeSession: { .shared(server) },
            now: { StorageHarness.date })
    }

    @Test func rustfsGetsLoopbackListenersKeyFilesAndARelativeVolume() {
        let request = Self.definition().serverRequest
        let root = "/Users/me/Library/Application Support/Jerd/storage"
        #expect(request.executable.path == StorageSettingsTests.runtime.path + "/rustfs")
        #expect(
            request.arguments == [
                "server", "--address", "127.0.0.1:9002", "--console-enable", "--console-address", "127.0.0.1:9003",
                "--access-key-file", "\(root)/access-key", "--secret-key-file", "\(root)/secret-key",
                "--region", "us-east-1", "data",
            ])
        #expect(request.workingDirectory.path == root)
        #expect(
            request.environment == [
                "RUSTFS_OBS_TRACES_EXPORT_ENABLED": "false", "RUSTFS_OBS_METRICS_EXPORT_ENABLED": "false",
                "RUSTFS_OBS_LOGS_EXPORT_ENABLED": "false", "RUSTFS_OBS_LOGGER_LEVEL": "warn",
                "RUSTFS_OBS_PROFILING_EXPORT_ENABLED": "false", "RUSTFS_CHECK_UPDATE": "false",
                "RUSTFS_CONSOLE_CORS_ALLOWED_ORIGINS": "http://127.0.0.1:9003",
                "RUSTFS_CORS_ALLOWED_ORIGINS": "http://127.0.0.1:9003",
            ])
    }

    @Test func theProfileNamesTheStorageRecordAndMessages() {
        let profile = Self.definition().profile
        #expect(profile.name == "RustFS" && profile.ports == [9_002, 9_003] && profile.stopSignal == SIGTERM)
        #expect(profile.record == Self.layout.storage.record)
        #expect(
            ServiceMessages.stopTimedOut(name: profile.name, timeout: .seconds(30))
                == "RustFS did not stop within 30 seconds. Its process is still tracked. "
                + "Retry Stop; Jerd did not force it to exit.")
    }

    @Test func theVersionRuleReadsOnlyTheFirstLine() {
        let probe = Self.definition().versionProbe
        #expect(probe.request.arguments == ["--version"])
        #expect(probe.rule.matches("rustfs 1.0.0\nbuild time: 2026\n"))
        #expect(probe.rule.matches("rustfs v1.0.0\n"))
        #expect(!probe.rule.matches("rustfs 2.0.0\npath /rustfs-1.0.0\n"))
        #expect(!probe.rule.matches("rustfs 1.0.01\n"))
        #expect(!probe.rule.matches("build\nrustfs 1.0.0\n"))
    }

    @Test func readinessNeedsASignedBucketListAndTheConsoleAndKeepsTheNames() async throws {
        let server = FakeS3Server()
        let launch = StorageLaunch()
        let id = launch.begin(.shared(server))
        server.update {
            $0.unavailableLists = 1
            $0.consoleStatus = 503
            $0.buckets = ["app-uploads"]
            $0.foreignNames = ["demo--x-s3"]
        }
        let probe = StorageReadinessProbe(
            client: S3Client(port: 9_002, credentials: S3ClientTests.credentials, sender: server), console: server,
            consoleURL: Self.definition().consoleURL, launch: launch, launchID: id)
        await #expect(throws: StorageMessages.httpStatus(503)) { try await probe.run() }
        #expect(try await probe.run() == .notReady("The RustFS console answered HTTP 503."))
        #expect(launch.names.isEmpty)
        server.update { $0.consoleStatus = 200 }
        #expect(try await probe.run() == .ready)
        #expect(launch.names == ["app-uploads"])
        #expect(server.keys.filter { $0.hasPrefix("GET /rustfs") }.count == 2)
        let check = probe.check
        #expect(
            check.deadline == .seconds(45) && check.interval == .milliseconds(150) && check.timeoutDetail == .logTail)
    }

    /// The console check has its own transport and a 3-second limit, so a hung console page
    /// cannot hold one readiness round for the whole session limit.
    @Test func theConsoleCheckUsesItsOwnTransportWithAShortLimit() async throws {
        let api = FakeS3Server()
        let console = FakeS3Server()
        let launch = StorageLaunch()
        let id = launch.begin(.shared(api))
        let probe = StorageReadinessProbe(
            client: S3Client(port: 9_002, credentials: S3ClientTests.credentials, sender: api), console: console,
            consoleURL: Self.definition().consoleURL, launch: launch, launchID: id)
        #expect(try await probe.run() == .ready)
        #expect(api.keys == ["GET /"])
        let request = try #require(console.current.requests.first)
        #expect(console.keys == ["GET /rustfs/console"])
        #expect(request.timeoutInterval == 3 && request.cachePolicy == .reloadIgnoringLocalCacheData)
    }
}
