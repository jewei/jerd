import Foundation
import JerdFoundation
import JerdManifest
import JerdProcess
import JerdRuntimes
import Testing

@testable import JerdDevKit

/// A JerdKit command runner that must not run: these tests prepare nothing new.
private struct UnusedCommands: CommandRunning {
    func run(_ request: ProcessRequest, timeout: Duration) async throws -> CommandResult {
        throw DevFailure.checkFailed("No command may run.")
    }
}

@Suite("Runtime prepare, verify, and status steps")
struct RuntimesStepsTests {
    @Test("Verify reports each payload and fails for a missing one")
    func verifyReportsMissing() async throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        try PayloadFixtures.writePayload(.mailpit, in: repository.payloads)
        let output = RecordingTextOutput()
        let context = TestFixtures.context(repository: repository, output: output)
        try await RuntimesVerifyStep.verify(context, groups: [.mail])
        #expect(output.all.contains("files match the receipt"))
        await #expect(throws: DevFailure.self) { try await RuntimesVerifyStep.verify(context, groups: [.storage]) }
        #expect(output.all.contains("is not prepared. Run ./dev runtimes prepare storage."))
    }

    @Test("Verify fails on a library reference that does not resolve inside the payload")
    func verifyChecksLibraryReferences() async throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let pin = try PayloadFixtures.pin(.mysql)
        let folder = repository.payloads.appending(path: "database/\(pin.id)")
        try PayloadFixture.writePayload(pin, in: folder)
        // The materialized libfido2 case: `bin/../lib/libcrypto.3.dylib` is not in the payload.
        let broken = "cmd LC_LOAD_DYLIB\nname @loader_path/../lib/libcrypto.3.dylib (offset 24)\n"
        let output = RecordingTextOutput()
        let failing = TestFixtures.context(
            repository: repository,
            runner: RecordingProcessRunner {
                InvocationResult(commandLine: $0.commandLine, status: 0, standardOutput: broken)
            },
            output: output)
        await #expect(throws: DevFailure.self) { try await RuntimesVerifyStep.verify(failing, groups: [.database]) }
        #expect(output.all.contains("bin/tool: tool needs @loader_path/../lib/libcrypto.3.dylib"))
        #expect(output.all.contains("remove .build/runtimes/payloads/database/\(pin.id)"))
        let system = "cmd LC_LOAD_DYLIB\nname /usr/lib/libSystem.B.dylib (offset 24)\n"
        let passing = TestFixtures.context(
            repository: repository,
            runner: RecordingProcessRunner {
                InvocationResult(commandLine: $0.commandLine, status: 0, standardOutput: system)
            },
            output: RecordingTextOutput())
        let entry = try #require(
            PayloadInventory(root: repository.payloads, catalog: try PayloadFixtures.catalog())
                .entry(for: pin, group: .database).payload)
        #expect(try await PayloadDependencyCheck(context: passing).problems(in: entry).isEmpty)
    }

    @Test("Prepare keeps an existing MySQL payload offline: a cached signature needs no network")
    func prepareWithCachedSignatureNeedsNoNetwork() async throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let pin = try PayloadFixtures.pin(.mysql)
        let pinned = try #require(pin.signature)
        let bytes = Data("signature".utf8)
        let signature = PinnedFile(
            url: pinned.url, sizeLimit: pinned.sizeLimit, sha256: FileDigest.hexSHA256(of: bytes))
        let output = RecordingTextOutput()
        let fetcher = FakeFetcher(files: [:])
        let step = RuntimesPrepareStep(
            context: TestFixtures.context(repository: repository, output: output), fetcher: fetcher,
            commands: UnusedCommands(), minimumMacOS: .jerdKitMinimum)
        // Offline and not cached: the step goes on, and a warning names the next step.
        await step.cacheSignature(signature, of: pin)
        #expect(output.all.contains("run ./dev runtimes prepare database once with a network connection"))
        // Cached with its pinned digest: no request at all.
        try FileManager.default.createDirectory(at: repository.runtimeDownloads, withIntermediateDirectories: true)
        try bytes.write(to: repository.runtimeDownloads.appending(path: signature.sha256))
        let requests = fetcher.requested.count
        await step.cacheSignature(signature, of: pin)
        #expect(fetcher.requested.count == requests)
    }

    @Test("Status lists every pin and the XZ library with its state")
    func statusListsEveryPin() throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        try PayloadFixtures.writePayload(.mailpit, in: repository.payloads)
        let output = RecordingTextOutput()
        try RuntimesVerifyStep.status(TestFixtures.context(repository: repository, output: output))
        let lines = output.all.split(separator: "\n")
        let pinCount = try PayloadFixtures.catalog().pins.count
        let mail = try PayloadFixtures.pin(.mailpit).id
        #expect(lines.count == pinCount + 2)
        #expect(lines.contains { $0.contains(mail) && $0.hasSuffix("valid") })
        #expect(lines.contains { $0.contains("xz-5.8.4") && $0.hasSuffix("missing") })
        let mysql = try PayloadFixtures.pin(.mysql).id
        #expect(lines.contains { $0.contains("database  ") && $0.contains("on demand") && $0.contains(mysql) })
        #expect(lines.contains { $0.contains("mail  ") && $0.contains(" yes ") })
        let redis = try PayloadFixtures.pin(.redis).id
        #expect(lines.contains { $0.contains("database  ") && $0.contains(" yes ") && $0.contains(redis) })
    }

    @Test("Status shows the PostgreSQL engine version, or names Postgres.app before the payload exists")
    func statusNamesThePostgresAppVersion() throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let pin = try PayloadFixtures.pin(.postgresql)
        let missing = RecordingTextOutput()
        try RuntimesVerifyStep.status(TestFixtures.context(repository: repository, output: missing))
        let missingRow = try #require(missing.all.split(separator: "\n").first { $0.contains(pin.id) })
        #expect(missingRow.contains("Postgres.app \(pin.version)"))
        try PayloadFixtures.writePayload(.postgresql, in: repository.payloads, version: "18.6")
        let prepared = RecordingTextOutput()
        try RuntimesVerifyStep.status(TestFixtures.context(repository: repository, output: prepared))
        let preparedRow = try #require(prepared.all.split(separator: "\n").first { $0.contains(pin.id) })
        #expect(preparedRow.contains(" 18.6 ") && !preparedRow.contains(pin.version))
    }

    @Test("Prepare verifies and keeps an earlier payload of the same pin without network")
    func prepareKeepsEarlierPayload() async throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        try PayloadFixtures.writePayload(.mailpit, in: repository.payloads)
        let output = RecordingTextOutput()
        let fetcher = FakeFetcher(files: [:])
        let step = RuntimesPrepareStep(
            context: TestFixtures.context(repository: repository, output: output), fetcher: fetcher,
            commands: UnusedCommands(), minimumMacOS: .jerdKitMinimum)
        try await step.prepare(.mail, catalog: try PayloadFixtures.catalog(), lzma: nil)
        #expect(fetcher.requested.isEmpty)
        #expect(output.all.contains("Verified the prepared \(try PayloadFixtures.pin(.mailpit).id)"))
        #expect(FileManager.default.fileExists(atPath: repository.payloads.appending(path: "runtimes.json").path))
    }

    @Test("A payload of another pin is preserved, and the message says how to prepare again")
    func preparePreservesOtherPin() async throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        let folder = try PayloadFixtures.writePayload(.mailpit, in: repository.payloads)
        let receipt = folder.appending(path: PayloadReceipt.fileName)
        let text = try String(contentsOf: receipt, encoding: .utf8)
        let pin = try PayloadFixtures.pin(.mailpit)
        try Data(text.replacingOccurrences(of: "\"\(pin.version)\"", with: "\"0.0.1\"").utf8).write(to: receipt)
        let step = RuntimesPrepareStep(
            context: TestFixtures.context(repository: repository), fetcher: FakeFetcher(files: [:]),
            commands: UnusedCommands(), minimumMacOS: .jerdKitMinimum)
        do {
            try await step.prepare(.mail, catalog: try PayloadFixtures.catalog(), lzma: nil)
            Issue.record("Expected a failure.")
        } catch let failure as DevFailure {
            #expect(failure.message.contains("It was preserved. Remove .build/runtimes/payloads"))
        }
        #expect(FileManager.default.fileExists(atPath: receipt.path))
    }

    @Test("Redis and XZ need the Xcode compiler; Mail alone does not")
    func compilerPrerequisite() async throws {
        let missing = RecordingProcessRunner { InvocationResult(commandLine: $0.commandLine, status: 1) }
        let step = RuntimesPrepareStep(
            context: TestFixtures.context(runner: missing), fetcher: FakeFetcher(files: [:]),
            commands: UnusedCommands(), minimumMacOS: .jerdKitMinimum
        )
        let catalog = try PayloadFixtures.catalog()
        try await step.checkPrerequisites(
            catalog: catalog, selection: RuntimeSelection(groups: [.mail], buildsXZ: false))
        #expect(missing.recorded.isEmpty)
        do {
            try await step.checkPrerequisites(catalog: catalog, selection: try RuntimeSelection.parse(["database"]))
            Issue.record("Expected a failure.")
        } catch let failure as DevFailure {
            #expect(failure.status == .missingPrerequisite)
            #expect(failure.message.contains("Xcode compiler"))
        }
        #expect(missing.recorded.map(\.arguments) == [["--find", "clang"]])
    }

    @Test("Progress messages print once until they change")
    func progressMessagesDeduplicate() {
        let messages = ProgressMessages()
        #expect(messages.isNew("Downloading…"))
        #expect(!messages.isNew("Downloading…"))
        #expect(messages.isNew("Checking…"))
    }
}
