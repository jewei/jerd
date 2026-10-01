import Foundation
import Testing
import Darwin
@testable import JerdCore

private func storageConfiguration(runtime: StorageRuntime) throws -> StorageConfiguration {
    let sockets = try ListeningSockets.bind(httpPort: 0, httpsPort: 0)
    defer { sockets.close() }
    let ports = try sockets.ports()
    var config = StorageConfiguration()
    config.runtime = runtime; config.apiPort = ports.http; config.consolePort = ports.https
    return config
}

struct StorageTests {
    @Test(arguments: ["UPPERCASE", "ab", "-uploads", "uploads-", "a..b", "a.-b", "a-.b", "127.0.0.1", "xn--bucket", "demo--x-s3", "a/b", "hello\nworld", "café", String(repeating: "a", count: 64)])
    func invalidBucketNamesAreRejected(_ name: String) {
        #expect(throws: (any Error).self) { try StorageBucket.validateName(name) }
    }
    @Test func settingsValidateAndKeepRuntimeIdentity() async throws {
        let root = try temporaryDirectory(" storage settings")
        defer { try? FileManager.default.removeItem(at: root) }
        try StorageBucket.validateName("my-app.uploads")
        let runtime = StorageRuntime(id: "rustfs-1.0.0", version: "1.0.0", path: "/test/runtime")
        var config = try storageConfiguration(runtime: runtime)
        config.buckets = [StorageBucket(name: "my-app-uploads")]
        let store = StorageStore(directory: root)
        try await store.save(config)
        #expect(try await store.load() == config)
        config.buckets.append(config.buckets[0])
        await #expect(throws: (any Error).self) { try await store.save(config) }
        config.buckets.removeLast()
        config.consolePort = config.apiPort
        #expect(throws: (any Error).self) { try config.validate() }
        config.consolePort = 80
        #expect(throws: (any Error).self) { try config.validate() }
        config = try await store.load()
        config.runtime = StorageRuntime(id: "other", version: "2.0.0", path: "/other")
        await #expect(throws: (any Error).self) { try await store.save(config) }
        #expect(try await store.load().runtime == runtime)
    }
    @Test(arguments: [Data(), Data("{\"schemaVersion\":999,\"apiPort\":9000,\"consolePort\":9001,\"buckets\":[]}".utf8)])
    func corruptSettingsArePreserved(_ bytes: Data) async throws {
        let root = try temporaryDirectory(" corrupt storage")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StorageStore(directory: root)
        let file = root.appendingPathComponent("settings.json")
        try bytes.write(to: file)
        await #expect(throws: (any Error).self) { try await store.load() }
        await #expect(throws: (any Error).self) { try await store.save(StorageConfiguration()) }
        #expect(try Data(contentsOf: file) == bytes)
    }
    @Test func credentialsAndLaravelSettingsUseTheOwnedService() throws {
        let credentials = try StorageCredentials.generate()
        try credentials.validate()
        let otherCredentials = try StorageCredentials.generate()
        #expect(credentials != otherCredentials)
        var config = StorageConfiguration(); config.apiPort = 19123
        let settings = config.laravelSettings(bucket: StorageBucket(name: "app-uploads"), credentials: credentials)
        #expect(settings.contains("AWS_ENDPOINT=http://127.0.0.1:19123\n"))
        #expect(settings.contains("AWS_URL=http://127.0.0.1:19123/app-uploads\n"))
        #expect(settings.contains("AWS_USE_PATH_STYLE_ENDPOINT=true\n"))
        let request = StorageDriver.server(configuration: config,
            runtime: StorageRuntime(id: "test", version: "1.0.0", path: "/private/runtime"), paths: StoragePaths(root: URL(fileURLWithPath: "/private/storage")))
        #expect(!request.arguments.contains(credentials.secretKey))
        #expect(!request.environment.values.contains(credentials.secretKey))
        #expect(request.arguments.contains("127.0.0.1:19123"))
        #expect(request.arguments.contains("--secret-key-file"))
        #expect(StorageS3Client.encode("/bucket/café +%?.txt", preserveSlash: true) == "/bucket/caf%C3%A9%20%2B%25%3F.txt")
    }
    @Test(arguments: [true, false])
    func occupiedPortsDoNotAffectOtherServices(api: Bool) async throws {
        let root = try temporaryDirectory(" storage conflict")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try storageConfiguration(runtime: StorageRuntime(id: "test", version: "1.0.0", path: "/missing"))
        try await StorageStore(directory: root).save(config)
        let port = api ? config.apiPort : config.consolePort
        let sockets = try ListeningSockets.bind(httpPort: port, httpsPort: 0)
        defer { sockets.close() }
        let manager = StorageManager(directory: root)
        _ = try await manager.load()
        await #expect(throws: (any Error).self) { try await manager.addBucket(name: "safe-uploads", publicRead: false) }
        let snapshot = await manager.snapshot()
        guard case .failed(let reason) = snapshot.state else { Issue.record("Expected port conflict"); return }
        #expect(reason.contains("occupied"))
        #expect(snapshot.processID == nil && snapshot.configuration.buckets.isEmpty)
        #expect(try sockets.ports().http == port)
        #expect(!FileManager.default.fileExists(atPath: StoragePaths(root: root).credentials.path))
    }
    @Test func previousProcessAndVersionMismatchArePreserved() async throws {
        struct WrongVersion: CommandRunning {
            func run(_ request: ProcessRequest, timeout: Duration) async throws -> CommandResult {
                if request.executable.lastPathComponent == "lsof" { return CommandResult(status: 1, output: "") }
                return CommandResult(status: 0, output: "rustfs 2.0.0\npath /rustfs-1.0.0\n")
            }
        }
        let root = try temporaryDirectory(" previous storage")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try storageConfiguration(runtime: StorageRuntime(id: "test", version: "1.0.0", path: "/rustfs-1.0.0"))
        try await StorageStore(directory: root).save(config)
        let paths = StoragePaths(root: root)
        let bytes = Data("{\"processID\":\(getpid()),\"runtimeID\":\"test\"}".utf8)
        try PrivateFiles.write(bytes, to: paths.activeRun)
        let manager = StorageManager(directory: root, commands: WrongVersion())
        _ = try await manager.load()
        await #expect(throws: (any Error).self) { try await manager.start() }
        #expect(try Data(contentsOf: paths.activeRun) == bytes)
        #expect(kill(getpid(), 0) == 0)
        try FileManager.default.removeItem(at: paths.activeRun)
        await #expect(throws: (any Error).self) { try await manager.start() }
        guard case .failed(let reason) = await manager.snapshot().state else { Issue.record("Expected version mismatch"); return }
        #expect(reason.contains("does not match"))
        #expect(!FileManager.default.fileExists(atPath: paths.data.path))
    }
}

struct StorageIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["JERD_STORAGE_INTEGRATION"] == "1",
                   "Select the prepared upstream RustFS runtime."))
    func saveCreatesReadyBucketsWithVerifiedAccessAndPersistentObjects() async throws {
        let runtimePath = try #require(ProcessInfo.processInfo.environment["JERD_STORAGE_RUNTIME"])
        let root = try temporaryDirectory(" storage persistence café")
        // Keep the fixture on failure for diagnosis; it contains only generated test data.
        let runtime = StorageRuntime(id: "rustfs-1.0.0-arm64", version: "1.0.0", path: runtimePath)
        let config = try storageConfiguration(runtime: runtime)
        let store = StorageStore(directory: root)
        try await store.save(config)
        let manager = StorageManager(directory: root)
        let paths = StoragePaths(root: root)
        _ = try await manager.load()
        do {
            // This is the complete Add bucket > Save flow. No manual Start call.
            try await manager.addBucket(name: "private-uploads", publicRead: false)
            var snapshot = await manager.snapshot()
            #expect(snapshot.state == .running && snapshot.processID != nil)
            #expect(snapshot.configuration.buckets.first?.setupComplete == true)
            #expect(snapshot.availableBuckets == ["private-uploads"])
            let credentials = try await manager.credentials()
            let client = StorageS3Client(port: config.apiPort, credentials: credentials)
            defer { client.close() }
            let wrong = StorageS3Client(port: config.apiPort,
                credentials: StorageCredentials(accessKey: credentials.accessKey, secretKey: String(repeating: "0", count: 48)))
            defer { wrong.close() }
            #expect(try await wrong.request("GET").status == 403)
            #expect(try await client.request("GET", authenticated: false).status == 403)

            let payload = Data([0, 1, 255, 128, 10]) + Data("Jerd café object\n".utf8)
            let key = "/private-uploads/folder/café +%?.bin"
            #expect(try await client.request("PUT", path: key, body: payload).status == 200)
            #expect(try await client.request("GET", path: key).data == payload)
            #expect(try await client.request("GET", path: key, authenticated: false).status == 403)
            await #expect(throws: (any Error).self) { try await manager.addBucket(name: "private-uploads", publicRead: false) }
            await #expect(throws: (any Error).self) { try await manager.edit(apiPort: config.apiPort, consolePort: config.consolePort) }
            try await manager.addBucket(name: "public-assets", publicRead: true)
            #expect(try await client.request("PUT", path: "/public-assets/hello.txt", body: payload).status == 200)
            #expect(try await client.request("GET", path: "/public-assets/hello.txt", authenticated: false).data == payload)
            #expect(try await client.request("PUT", path: "/public-assets/forbidden.txt", body: payload, authenticated: false).status == 403)
            #expect(try await client.request("DELETE", path: "/public-assets/hello.txt", authenticated: false).status == 403)
            #expect(try await client.request("GET", path: "/public-assets", authenticated: false).status == 403)

            // Independent curl signer proves compatibility with a separate S3 client.
            let curlConfig = root.appendingPathComponent("s3-client.conf")
            try PrivateFiles.write(Data("user = \"\(credentials.accessKey):\(credentials.secretKey)\"\naws-sigv4 = \"aws:amz:us-east-1:s3\"\n".utf8), to: curlConfig)
            let file = root.appendingPathComponent("curl-object.bin")
            try PrivateFiles.write(payload, to: file)
            let curl = try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/curl"),
                arguments: ["--config", curlConfig.path, "--silent", "--show-error", "--fail", "--max-time", "5", "--noproxy", "*",
                            "--upload-file", file.path, "\(config.endpoint.absoluteString)/private-uploads/curl.bin"], directory: root), timeout: .seconds(7))
            #expect(curl.status == 0)
            #expect(try await client.request("GET", path: "/private-uploads/curl.bin").data == payload)

            for file in [paths.credentials, paths.accessKey, paths.secretKey, paths.activeRun] {
                #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            }
            #expect((try FileManager.default.attributesOfItem(atPath: paths.data.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
            try await manager.stop()
            #expect(await manager.snapshot().state == .stopped)
            #expect(!FileManager.default.fileExists(atPath: paths.activeRun.path))
            #expect(FileManager.default.fileExists(atPath: paths.format.path))
            let changed = try storageConfiguration(runtime: runtime)
            try await manager.edit(apiPort: changed.apiPort, consolePort: changed.consolePort)
            try await manager.edit(apiPort: config.apiPort, consolePort: config.consolePort)
            try await manager.start()
            #expect(try await client.request("GET", path: key).data == payload)
            #expect(try await client.request("GET", path: "/public-assets/hello.txt", authenticated: false).data == payload)
            #expect(try await manager.credentials() == credentials)
            snapshot = await manager.snapshot()
            #expect(snapshot.availableBuckets == ["private-uploads", "public-assets"])

            let pid = try #require(snapshot.processID)
            #expect(kill(pid, SIGTERM) == 0)
            let deadline = ContinuousClock.now + .seconds(10)
            while await manager.snapshot().processID != nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
            guard case .failed = await manager.snapshot().state else { Issue.record("Process exit was not detected"); return }
            try await manager.start()
            try await manager.stop()

            let format = try Data(contentsOf: paths.format)
            try FileManager.default.removeItem(at: paths.format)
            await #expect(throws: (any Error).self) { try await manager.start() }
            #expect(!FileManager.default.fileExists(atPath: paths.format.path))
            try PrivateFiles.write(format, to: paths.format)
            let credentialBytes = try Data(contentsOf: paths.credentials)
            try FileManager.default.removeItem(at: paths.credentials)
            await #expect(throws: (any Error).self) { try await manager.start() }
            #expect(!FileManager.default.fileExists(atPath: paths.credentials.path))
            try PrivateFiles.write(credentialBytes, to: paths.credentials)
            let identity = try Data(contentsOf: paths.identity)
            try PrivateFiles.write(JSONEncoder().encode(StorageRuntime(id: "different", version: "2.0.0", path: runtimePath)), to: paths.identity)
            await #expect(throws: (any Error).self) { try await manager.start() }
            try PrivateFiles.write(identity, to: paths.identity)

            // Resume an interrupted setup across a manager/app restart.
            var pending = try await store.load()
            pending.buckets.append(StorageBucket(name: "pending-bucket", publicRead: true))
            try await store.save(pending)
            let restored = StorageManager(directory: root)
            _ = try await restored.load()
            do {
                try await restored.retryBucket("pending-bucket")
                #expect(await restored.snapshot().configuration.buckets.last?.setupComplete == true)
                #expect(try await client.request("GET", path: key).data == payload)
                try await restored.stop()
            } catch { try? await restored.stop(); throw error }
            try FileManager.default.removeItem(at: root)
        } catch {
            try? await manager.stop()
            Issue.record("Storage fixture retained at \(root.path)")
            throw error
        }
    }
}
