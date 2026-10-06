import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdStorage

/// An opt-in test with a real RustFS 1.0.0 runtime. It uses a temporary data folder and free
/// loopback ports only.
@Suite(.serialized) struct StorageIntegrationTests {
    static let environment = ProcessInfo.processInfo.environment
    static let payload = Data([0, 1, 255, 128, 10]) + Data("Jerd café object\n".utf8)
    static let key = "/private-uploads/folder/café +%?.bin"

    @Test(.enabled(if: environment["JERD_STORAGE_INTEGRATION"] == "1" && environment["JERD_STORAGE_RUNTIME"] != nil))
    func saveCreatesVerifiedBucketsAndKeepsObjectsAcrossRestartsAndUpdates() async throws {
        let folder = URL(fileURLWithPath: try #require(Self.environment["JERD_STORAGE_RUNTIME"]))
        let run = try await StorageIntegrationRun(runtime: folder)
        do {
            try await savePrivateBucketWithoutAStart(run)
            try await savePublicBucketWithReadOnlyAccess(run)
            try await interoperateWithCurlSigV4(run)
            try await keepObjectsAcrossAPortChange(run)
            try await updateAndRollBack(run)
            try await detectAnExternalStop(run)
            try await refuseTamperedData(run)
            try await retryAnInterruptedSetupAfterARestart(run)
            run.directory.remove()
        } catch {
            do {
                try await run.manager.stop()
            } catch {
                Issue.record("Storage cleanup failed.")
            }
            Issue.record("Storage test data was kept in \(run.directory.url.path).")
            throw error
        }
    }

    private func savePrivateBucketWithoutAStart(_ run: StorageIntegrationRun) async throws {
        try await run.manager.addBucket(name: "private-uploads", publicRead: false)
        let snapshot = await run.manager.snapshot()
        #expect(snapshot.processID != nil && snapshot.availableBuckets == ["private-uploads"])
        #expect(snapshot.settings.buckets.first?.setupComplete == true)
        let client = try await run.client()
        let saved = try await run.manager.credentials()
        let wrong = StorageCredentials(accessKey: saved.accessKey, secretKey: String(repeating: "0", count: 48))
        #expect(try await run.client(wrong).send("GET").status == 403)
        #expect(try await client.send("GET", signed: false).status == 403)
        #expect(try await client.send("PUT", path: Self.key, body: Self.payload).status == 200)
        #expect(try await client.send("GET", path: Self.key).body == Self.payload)
        #expect(try await client.send("GET", path: Self.key, signed: false).status == 403)
        await #expect(throws: (any Error).self) {
            try await run.manager.addBucket(name: "private-uploads", publicRead: false)
        }
        await #expect(throws: (any Error).self) {
            try await run.manager.edit(ports: try StorageIntegrationRun.freePorts())
        }
    }

    private func savePublicBucketWithReadOnlyAccess(_ run: StorageIntegrationRun) async throws {
        try await run.manager.addBucket(name: "public-assets", publicRead: true)
        let client = try await run.client()
        #expect(try await client.send("PUT", path: "/public-assets/hello.txt", body: Self.payload).status == 200)
        #expect(try await client.send("GET", path: "/public-assets/hello.txt", signed: false).body == Self.payload)
        let put = try await client.send("PUT", path: "/public-assets/no.txt", body: Self.payload, signed: false)
        #expect(put.status == 403)
        #expect(try await client.send("DELETE", path: "/public-assets/hello.txt", signed: false).status == 403)
        #expect(try await client.send("GET", path: "/public-assets", signed: false).status == 403)
    }

    private func interoperateWithCurlSigV4(_ run: StorageIntegrationRun) async throws {
        let credentials = try await run.manager.credentials()
        let config = run.directory.path("s3-client.conf")
        let text =
            "user = \"\(credentials.accessKey):\(credentials.secretKey)\"\naws-sigv4 = \"aws:amz:us-east-1:s3\"\n"
        try AtomicFile.write(Data(text.utf8), to: config)
        let file = run.directory.path("curl-object.bin")
        try AtomicFile.write(Self.payload, to: file)
        let endpoint = await run.manager.snapshot().settings.endpoint
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: "/usr/bin/curl"),
            arguments: [
                "--config", config.path, "--silent", "--show-error", "--fail", "--max-time", "5", "--noproxy", "*",
                "--upload-file", file.path, "\(endpoint)/private-uploads/curl.bin",
            ], workingDirectory: run.directory.url)
        let result = try await CommandRunner().run(request, timeout: .seconds(7))
        #expect(result.succeeded, "\(result.output)")
        #expect(try await run.client().send("GET", path: "/private-uploads/curl.bin").body == Self.payload)
        for file in [run.storage.credentialsFile, run.storage.accessKeyFile, run.storage.secretKeyFile] {
            #expect(mode(file) == 0o600)
        }
        #expect(mode(run.storage.activeRunFile) == 0o600 && mode(run.storage.dataDirectory) == 0o700)
    }

    private func keepObjectsAcrossAPortChange(_ run: StorageIntegrationRun) async throws {
        let credentials = try await run.manager.credentials()
        try await run.manager.stop()
        #expect(await run.manager.snapshot().state == .stopped)
        #expect(!exists(run.storage.activeRunFile) && exists(run.storage.formatFile))
        try await run.manager.edit(ports: try StorageIntegrationRun.freePorts())
        try await run.manager.start()
        let client = try await run.client()
        #expect(try await client.send("GET", path: Self.key).body == Self.payload)
        #expect(try await client.send("GET", path: "/public-assets/hello.txt", signed: false).body == Self.payload)
        #expect(try await run.manager.credentials() == credentials)
        #expect(await run.manager.snapshot().availableBuckets == ["private-uploads", "public-assets"])
    }

    private func updateAndRollBack(_ run: StorageIntegrationRun) async throws {
        let updated = StorageRuntime(id: "rustfs-update-test", version: run.runtime.version, path: run.runtime.path)
        try await run.manager.updateRuntime(updated)
        #expect(await run.manager.snapshot().settings.runtime == updated)
        #expect(try await run.client().send("GET", path: Self.key).body == Self.payload)
        let invalid = StorageRuntime(id: "rustfs-invalid-update", version: "99.0.0", path: run.runtime.path)
        await #expect(throws: (any Error).self) { try await run.manager.updateRuntime(invalid) }
        let snapshot = await run.manager.snapshot()
        #expect(snapshot.settings.runtime == updated && snapshot.processID != nil)
        #expect(try await run.client().send("GET", path: Self.key).body == Self.payload)
        let backups = try FileManager.default.contentsOfDirectory(atPath: run.storage.runtimeBackupsDirectory.path)
        #expect(backups.count == 2)
    }

    private func detectAnExternalStop(_ run: StorageIntegrationRun) async throws {
        let pid = try #require(await run.manager.snapshot().processID)
        #expect(kill(pid, SIGTERM) == 0)
        #expect(await eventually(timeout: .seconds(15)) { await run.manager.snapshot().state.failure != nil })
        try await run.manager.start()
        try await run.manager.stop()
    }

    private func refuseTamperedData(_ run: StorageIntegrationRun) async throws {
        for file in [run.storage.formatFile, run.storage.credentialsFile] {
            let bytes = try #require(contents(file))
            try FileManager.default.removeItem(at: file)
            await #expect(throws: StorageMessages.requiredFileInvalid) { try await run.manager.start() }
            #expect(!exists(file))
            try AtomicFile.write(bytes, to: file)
        }
        let identity = try #require(contents(run.storage.runtimeIdentityFile))
        try MarkerFile.write(
            StorageRuntime(id: "different", version: "2.0.0", path: run.runtime.path),
            to: run.storage.runtimeIdentityFile)
        await #expect(throws: (any Error).self) { try await run.manager.start() }
        try AtomicFile.write(identity, to: run.storage.runtimeIdentityFile)
    }

    private func retryAnInterruptedSetupAfterARestart(_ run: StorageIntegrationRun) async throws {
        let store = StorageSettingsStore(layout: run.storage)
        var pending = try store.load()
        pending.buckets.append(StorageBucket(name: "pending-bucket", publicRead: true))
        try store.save(pending)
        let restarted = StorageIntegrationRun.manager(run.layout)
        _ = try await restarted.load()
        try await restarted.retryBucket("pending-bucket")
        #expect(await restarted.snapshot().settings.buckets.last?.setupComplete == true)
        #expect(try await run.client().send("GET", path: Self.key).body == Self.payload)
        try await restarted.stop()
    }
}
