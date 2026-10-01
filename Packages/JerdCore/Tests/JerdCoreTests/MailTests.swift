import Foundation
import Testing
import Darwin
@testable import JerdCore

private func mailConfiguration(runtime: MailRuntime) throws -> MailConfiguration {
    let sockets = try ListeningSockets.bind(httpPort: 0, httpsPort: 0)
    defer { sockets.close() }
    let ports = try sockets.ports()
    var config = MailConfiguration()
    config.runtime = runtime; config.smtpPort = ports.http; config.webPort = ports.https
    return config
}

struct MailTests {
    @Test func aVersionInTheRuntimePathDoesNotPassTheVersionCheck() async throws {
        struct WrongVersion: CommandRunning {
            func run(_ request: ProcessRequest, timeout: Duration) async throws -> CommandResult {
                if request.executable.lastPathComponent == "lsof" { return CommandResult(status: 1, output: "") }
                return CommandResult(status: 0, output: request.executable.path + " v2.0.0 compiled with go on darwin/arm64\n")
            }
        }
        let root = try temporaryDirectory(" wrong mail version")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try mailConfiguration(runtime: MailRuntime(id: "mailpit-1.31.3", version: "1.31.3", path: "/test/mailpit-1.31.3"))
        try await MailStore(directory: root).save(config)
        let manager = MailManager(directory: root, commands: WrongVersion())
        _ = try await manager.load()
        await #expect(throws: (any Error).self) { try await manager.start() }
        guard case .failed(let reason) = await manager.snapshot().state else { Issue.record("Expected version mismatch"); return }
        #expect(reason.contains("does not match"))
        #expect(!FileManager.default.fileExists(atPath: MailPaths(root: root).inbox.path))
    }

    @Test(arguments: [Data(), Data("{\"schemaVersion\":999,\"smtpPort\":1025,\"webPort\":8025}".utf8)])
    func corruptSettingsCannotBeOverwritten(_ bytes: Data) async throws {
        let root = try temporaryDirectory(" mail settings")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MailStore(directory: root)
        let file = root.appendingPathComponent("settings.json")
        try bytes.write(to: file)
        await #expect(throws: (any Error).self) { try await store.load() }
        await #expect(throws: (any Error).self) { try await store.save(MailConfiguration()) }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func settingsKeepTheRuntimeAndUseLocalSMTP() async throws {
        let root = try temporaryDirectory(" mail identity")
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = MailRuntime(id: "mailpit-test", version: "1.31.3", path: "/test/runtime")
        var config = try mailConfiguration(runtime: runtime)
        let store = MailStore(directory: root)
        try await store.save(config)
        #expect(try await store.load() == config)
        #expect(config.laravelSettings.contains("MAIL_PORT=\(config.smtpPort)\n"))
        #expect(config.laravelSettings.contains("MAIL_URL=null\nMAIL_HOST=127.0.0.1\n"))
        #expect(config.laravelSettings.contains("MAIL_PASSWORD=null"))
        config.runtime = MailRuntime(id: "mailpit-new", version: "2.0.0", path: "/test/new")
        await #expect(throws: (any Error).self) { try await store.save(config) }
        #expect(try await store.load().runtime == runtime)
        config.runtime = runtime
        config.webPort = config.smtpPort
        #expect(throws: (any Error).self) { try config.validate() }
        config.webPort = 80
        #expect(throws: (any Error).self) { try config.validate() }
    }

    @Test(arguments: [true, false])
    func occupiedMailPortPreservesTheOtherService(smtp: Bool) async throws {
        let root = try temporaryDirectory(" mail conflict")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = try mailConfiguration(runtime: MailRuntime(id: "test", version: "1.31.3", path: "/missing-runtime"))
        try await MailStore(directory: root).save(config)
        let occupiedPort = smtp ? config.smtpPort : config.webPort
        let sockets = try ListeningSockets.bind(httpPort: occupiedPort, httpsPort: 0)
        defer { sockets.close() }
        let manager = MailManager(directory: root)
        _ = try await manager.load()
        await #expect(throws: (any Error).self) { try await manager.start() }
        let snapshot = await manager.snapshot()
        guard case .failed(let reason) = snapshot.state else { Issue.record("Expected occupied-port failure"); return }
        #expect(reason.contains("occupied"))
        #expect(snapshot.processID == nil)
        #expect(try sockets.ports().http == occupiedPort)
        #expect(!FileManager.default.fileExists(atPath: MailPaths(root: root).inbox.path))
    }

    @Test func aPreviousLiveProcessIsNeverSignalled() async throws {
        let root = try temporaryDirectory(" previous mail")
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = MailRuntime(id: "test", version: "1.31.3", path: "/missing-runtime")
        let config = try mailConfiguration(runtime: runtime)
        try await MailStore(directory: root).save(config)
        let bytes = Data("{\"processID\":\(getpid()),\"runtimeID\":\"test\"}".utf8)
        let file = MailPaths(root: root).activeRun
        try PrivateFiles.write(bytes, to: file)
        let manager = MailManager(directory: root)
        _ = try await manager.load()
        await #expect(throws: (any Error).self) { try await manager.start() }
        #expect(try Data(contentsOf: file) == bytes)
        #expect(kill(getpid(), 0) == 0)
        #expect(await manager.snapshot().processID == nil)
    }
}

struct MailIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["JERD_MAIL_INTEGRATION"] == "1",
                   "Select the prepared upstream Mailpit runtime."))
    func smtpCapturesMIMEAndRetainsMessagesAcrossRestart() async throws {
        let runtimePath = try #require(ProcessInfo.processInfo.environment["JERD_MAIL_RUNTIME"])
        let root = try temporaryDirectory(" mail persistence café")
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = MailRuntime(id: "mailpit-1.31.3-arm64", version: "1.31.3", path: runtimePath)
        let config = try mailConfiguration(runtime: runtime)
        try await MailStore(directory: root).save(config)
        let manager = MailManager(directory: root)
        let paths = MailPaths(root: root)
        _ = try await manager.load()

        func get(_ path: String, headers: [String] = []) async throws -> CommandResult {
            try await LocalCommandRunner().run(ProcessRequest(executable: URL(fileURLWithPath: "/usr/bin/curl"),
                arguments: ["--silent", "--show-error", "--max-time", "3", "--noproxy", "*"] + headers +
                    [config.inboxURL.appendingPathComponent(path).absoluteString], directory: root), timeout: .seconds(5))
        }
        func object(_ path: String) async throws -> [String: Any] {
            let result = try await get(path)
            #expect(result.status == 0)
            return try #require(JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
        }

        do {
            try await manager.start()
            let snapshot = await manager.snapshot()
            #expect(snapshot.state == .running && snapshot.processID != nil)
            let info = try await object("api/v1/info")
            #expect(info["Version"] as? String == "v1.31.3")
            #expect(info["LatestVersion"] as? String == "disabled")
            #expect(info["Messages"] as? Int == 0)
            let rejected = try await get("api/v1/info", headers: ["--header", "Host: untrusted.example.test", "--write-out", "%{http_code}"])
            #expect(rejected.output.hasSuffix("403"))

            let message = root.appendingPathComponent("fixture.eml")
            let attachment = "Jerd attachment\n"
            let subject = "Jerd mail: café"
            let mime = [
                "From: Sender <hello@jerd.test>", "To: Receiver <inbox@jerd.test>",
                "Subject: =?UTF-8?B?\(Data(subject.utf8).base64EncodedString())?=",
                "Message-ID: <\(UUID().uuidString)@jerd.test>", "MIME-Version: 1.0",
                "Content-Type: multipart/mixed; boundary=jerd-mixed", "",
                "--jerd-mixed", "Content-Type: multipart/alternative; boundary=jerd-body", "",
                "--jerd-body", "Content-Type: text/plain; charset=UTF-8", "", "Plain café body.",
                "--jerd-body", "Content-Type: text/html; charset=UTF-8", "", "<p>HTML café body.</p>",
                "--jerd-body--", "--jerd-mixed", "Content-Type: text/plain; name=report.txt",
                "Content-Disposition: attachment; filename=report.txt", "Content-Transfer-Encoding: base64", "",
                Data(attachment.utf8).base64EncodedString(), "--jerd-mixed--", ""
            ].joined(separator: "\r\n")
            try PrivateFiles.write(Data(mime.utf8), to: message)
            let sent = try await LocalCommandRunner().run(MailDriver.send(configuration: config, paths: paths, message: message), timeout: .seconds(7))
            #expect(sent.status == 0, "\(sent.output)")
            let captured = try await object("api/v1/message/latest")
            #expect(captured["Subject"] as? String == subject)
            #expect((captured["Text"] as? String)?.contains("Plain café body.") == true)
            #expect((captured["HTML"] as? String)?.contains("<p>HTML café body.</p>") == true)
            let attachments = try #require(captured["Attachments"] as? [[String: Any]])
            #expect(attachments.count == 1)
            let item = try #require(attachments.first)
            #expect(item["FileName"] as? String == "report.txt")
            let id = try #require(captured["ID"] as? String)
            let part = try #require(item["PartID"] as? String)
            let downloaded = try await get("api/v1/message/\(id)/part/\(part)")
            #expect(downloaded.output == attachment)
            let permissions = try FileManager.default.attributesOfItem(atPath: paths.database.path)[.posixPermissions] as? NSNumber
            #expect(permissions?.intValue == 0o600)

            await #expect(throws: (any Error).self) { try await manager.edit(smtpPort: config.smtpPort, webPort: config.webPort) }
            try await manager.sendTestEmail()
            let totals = try await object("api/v1/info")
            #expect(totals["Messages"] as? Int == 2)
            try await manager.stop()
            #expect(await manager.snapshot().state == .stopped)
            #expect(FileManager.default.fileExists(atPath: paths.database.path))
            #expect(!FileManager.default.fileExists(atPath: paths.activeRun.path))

            let changed = try mailConfiguration(runtime: runtime)
            try await manager.edit(smtpPort: changed.smtpPort, webPort: changed.webPort)
            // Restore the original ports so the same API helpers can verify persistence.
            try await manager.edit(smtpPort: config.smtpPort, webPort: config.webPort)
            try await manager.start()
            let restored = try await object("api/v1/message/\(id)")
            #expect(restored["Subject"] as? String == subject)
            let after = try await object("api/v1/info")
            #expect(after["Messages"] as? Int == 2)

            let active = await manager.snapshot()
            let ownedPID = try #require(active.processID)
            #expect(kill(ownedPID, SIGTERM) == 0)
            let deadline = ContinuousClock.now + .seconds(5)
            while await manager.snapshot().processID != nil, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(30))
            }
            guard case .failed = await manager.snapshot().state else { Issue.record("Process exit was not detected"); return }
            try await manager.start()
            try await manager.stop()

            let retained = root.appendingPathComponent("retained.sqlite")
            try FileManager.default.moveItem(at: paths.database, to: retained)
            await #expect(throws: (any Error).self) { try await manager.start() }
            #expect(!FileManager.default.fileExists(atPath: paths.database.path))
            try FileManager.default.moveItem(at: retained, to: paths.database)
            let originalIdentity = try Data(contentsOf: paths.identity)
            try PrivateFiles.write(JSONEncoder().encode(MailRuntime(id: "other", version: "2.0", path: runtimePath)), to: paths.identity)
            await #expect(throws: (any Error).self) { try await manager.start() }
            try PrivateFiles.write(originalIdentity, to: paths.identity)
            try await manager.start()
            let final = try await object("api/v1/info")
            #expect(final["Messages"] as? Int == 2)
            try await manager.stop()
        } catch { try? await manager.stop(); throw error }
    }
}
