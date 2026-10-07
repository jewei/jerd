import Foundation
import Testing

@testable import JerdDevKit

@Suite("Harness run and system facts")
struct HarnessRunTests {
    /// Answers the fact commands like a clean checkout on macOS 27.
    static let factsRunner = RecordingProcessRunner { invocation in
        let output: String
        switch (invocation.executable.lastPathComponent, invocation.arguments.last) {
        case ("sw_vers", _): output = "27.0\n"
        case ("xcodebuild", _): output = "Xcode 27.0\nBuild version 27A100\n"
        case ("git", "HEAD"): output = String(repeating: "b", count: 40) + "\n"
        default: output = ""
        }
        return InvocationResult(commandLine: invocation.commandLine, status: 0, standardOutput: output)
    }

    private func records(in root: URL) throws -> [EvidenceRecord] {
        let folder = root.appending(path: ".build/evidence")
        return try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted().map {
            try JSONDecoder().decode(EvidenceRecord.self, from: Data(contentsOf: folder.appending(path: $0)))
        }
    }

    @Test("Reads the macOS, Xcode, commit, and clean state")
    func readsFacts() async {
        let context = TestFixtures.context(runner: Self.factsRunner)
        let facts = await SystemFacts.read(context)
        #expect(
            facts
                == SystemFacts(
                    macOSVersion: "27.0", xcodeVersion: "Xcode 27.0 Build version 27A100",
                    commit: String(repeating: "b", count: 40), dirty: false))
    }

    @Test("A fact that cannot be read is unknown, and an unknown state counts as dirty")
    func unknownFacts() async {
        let runner = RecordingProcessRunner { InvocationResult(commandLine: $0.commandLine, status: 1) }
        let facts = await SystemFacts.read(TestFixtures.context(runner: runner))
        #expect(facts == SystemFacts(macOSVersion: "unknown", xcodeVersion: "unknown", commit: "unknown", dirty: true))
    }

    @Test("Writes a passed record and succeeds")
    func writesPassedRecord() async throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let context = TestFixtures.context(repository: Repository(root: root), runner: Self.factsRunner)
        let harness = HarnessRun(check: "xpc", identity: "ID", context: context, clock: FakeHarnessClock())
        try await harness.run { $0.append(.init(name: "allow", passed: true, detail: "passed")) }
        let record = try #require(try records(in: root).first)
        #expect(record.passed && record.cases.count == 1 && record.date == "2026-10-06T09:15:00Z")
    }

    @Test("Writes the record of a stopped run with its cases and rethrows the error")
    func writesStoppedRecord() async throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let context = TestFixtures.context(repository: Repository(root: root), runner: Self.factsRunner)
        let harness = HarnessRun(check: "updates", identity: "ID", context: context, clock: FakeHarnessClock())
        await #expect(throws: DevFailure.missingPrerequisite("No key.")) {
            try await harness.run { cases in
                cases.append(.init(name: "first", passed: true, detail: "passed"))
                throw DevFailure.missingPrerequisite("No key.")
            }
        }
        let record = try #require(try records(in: root).first)
        #expect(record.result == "failed" && record.message == "No key." && record.cases.map(\.name) == ["first"])
    }

    @Test("A failed case fails the run after the record is written")
    func failedCaseFails() async throws {
        let root = try TestFixtures.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let context = TestFixtures.context(repository: Repository(root: root), runner: Self.factsRunner)
        let harness = HarnessRun(check: "updates", identity: "ID", context: context, clock: FakeHarnessClock())
        await #expect(throws: DevFailure.self) {
            try await harness.run { $0.append(.init(name: "success", passed: false, detail: "Not version 2.")) }
        }
        #expect(try records(in: root).first?.result == "failed")
    }
}
