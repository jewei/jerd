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
    func verifyReportsMissing() throws {
        let repository = try PayloadFixtures.repository()
        defer { try? FileManager.default.removeItem(at: repository.root) }
        try PayloadFixtures.writePayload(.mailpit, in: repository.payloads)
        let output = RecordingTextOutput()
        let context = TestFixtures.context(repository: repository, output: output)
        try RuntimesVerifyStep.verify(context, groups: [.mail])
        #expect(output.all.contains("files match the receipt"))
        #expect(throws: DevFailure.self) { try RuntimesVerifyStep.verify(context, groups: [.storage]) }
        #expect(output.all.contains("is not prepared. Run ./dev runtimes prepare storage."))
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
            commands: UnusedCommands())
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
            commands: UnusedCommands())
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
            context: TestFixtures.context(runner: missing), fetcher: FakeFetcher(files: [:]), commands: UnusedCommands()
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
