import Darwin
import Foundation
import JerdFoundation
import Testing
import os

@testable import JerdSystem

/// Fault injection into the generic step runner: every step, every compensation failure, exact phases.
@Suite struct SetupTransactionTests {
    private final class Log: Sendable {
        let entries = OSAllocatedUnfairLock(initialState: [String]())
        func add(_ entry: String) { entries.withLock { $0.append(entry) } }
        var all: [String] { entries.withLock { $0 } }
    }

    private struct Injected: Error {}

    private func step(
        _ name: String, log: Log, failApply: Bool = false, failUndo: Bool = false,
        failure: SetupStep.Failure = .init()
    ) -> SetupStep {
        SetupStep(
            label: name, startPhase: "start \(name)", donePhase: "done \(name)",
            apply: {
                log.add("apply \(name)")
                if failApply { throw JerdError.unavailable("apply \(name) failed") }
            },
            undo: {
                log.add("undo \(name)")
                if failUndo { throw JerdError.unavailable("undo \(name) failed") }
            },
            classify: { _ in failure })
    }

    private func journal() throws -> SetupJournal {
        guard
            case .journal(let journal) = try HelperRecordCodec.decodePending(
                Fixture.data("Records/pending-configure.json"))
        else { throw Injected() }
        return journal
    }

    private func phase(_ directory: RootRecordDirectory) throws -> String? {
        guard let bytes = try directory.read(.pending),
            case .journal(let journal) = try HelperRecordCodec.decodePending(bytes)
        else { return nil }
        return journal.phase
    }

    @Test func successRunsEveryStepInOrderAndDeletesTheJournal() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let directory = RootRecordDirectory(url: folder.path("helper"), owner: getuid())
        let log = Log()
        var transaction = SetupTransaction(
            directory: directory, journal: try journal(), steps: [step("a", log: log), step("b", log: log)],
            failureTitle: "Setup failed")
        try await transaction.run()
        #expect(log.all == ["apply a", "apply b"])
        #expect(!directory.exists(.pending))
        #expect(transaction.journal.phase == "done b")
    }

    /// Regression test: when only the journal deletion fails, no applied step is undone. The journal
    /// stays with an "Applied" phase, and the error is a partial change.
    @Test func aFailedCommitKeepsEveryStepAndTheJournal() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let directory = RootRecordDirectory(url: folder.path("helper"), owner: getuid())
        let log = Log()
        var transaction = SetupTransaction(
            directory: directory, journal: try journal(), steps: [step("a", log: log), step("b", log: log)],
            failureTitle: "Setup failed", commit: { _ in throw JerdError.unavailable("unlink failed") })
        await #expect(
            throws: JerdError.partialChange(
                "Setup failed after every change was applied, and needs recovery. unlink failed")
        ) {
            try await transaction.run()
        }
        #expect(log.all == ["apply a", "apply b"])
        #expect(try phase(directory) == "Applied; the recovery record could not be removed.")
    }

    @Test(arguments: [0, 1, 2])
    func aFailureUndoesOnlyCompletedStepsInReverseAndRethrows(failing: Int) async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let directory = RootRecordDirectory(url: folder.path("helper"), owner: getuid())
        let log = Log()
        let steps = (0..<3).map { step("s\($0)", log: log, failApply: $0 == failing) }
        var transaction = SetupTransaction(
            directory: directory, journal: try journal(), steps: steps, failureTitle: "Setup failed")
        await #expect(throws: JerdError.unavailable("apply s\(failing) failed")) { try await transaction.run() }
        let undone = (0..<failing).reversed().map { "undo s\($0)" }
        #expect(log.all == (0...failing).map { "apply s\($0)" } + undone)
        #expect(!directory.exists(.pending))
    }

    @Test func aStepWhoseEffectMayRemainIsUndoneToo() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let directory = RootRecordDirectory(url: folder.path("helper"), owner: getuid())
        let log = Log()
        let steps = [step("a", log: log), step("b", log: log, failApply: true, failure: .init(undo: true))]
        var transaction = SetupTransaction(
            directory: directory, journal: try journal(), steps: steps, failureTitle: "Setup failed")
        await #expect(throws: JerdError.self) { try await transaction.run() }
        #expect(log.all == ["apply a", "apply b", "undo b", "undo a"])
    }

    @Test(arguments: [0, 1])
    func aFailedUndoKeepsTheJournalWithASummary(failingUndo: Int) async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let directory = RootRecordDirectory(url: folder.path("helper"), owner: getuid())
        let log = Log()
        let steps = [
            step("hosts", log: log, failUndo: failingUndo == 0), step("trust", log: log, failUndo: failingUndo == 1),
            step("record", log: log, failApply: true),
        ]
        var transaction = SetupTransaction(
            directory: directory, journal: try journal(), steps: steps, failureTitle: "Removal failed")
        do {
            try await transaction.run()
            Issue.record("Expected a failure")
        } catch let error as JerdError {
            #expect(error.kind == .partialChange)
            let failed = failingUndo == 0 ? "hosts" : "trust"
            #expect(
                error.message
                    == "Removal failed and needs recovery. The helper retained its backup. apply record failed undo \(failed) failed"
            )
        }
        let summary =
            failingUndo == 0
            ? " Rolled back: trust. Rollback failed: hosts." : " Rolled back: hosts. Rollback failed: trust."
        #expect(try phase(directory) == "start record." + summary)
    }

    @Test func aRetainNoteKeepsTheJournalAfterACleanRollback() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let directory = RootRecordDirectory(url: folder.path("helper"), owner: getuid())
        let log = Log()
        let steps = [
            step("a", log: log),
            step("b", log: log, failApply: true, failure: .init(phase: "b needs recovery", retainNote: "note")),
        ]
        var transaction = SetupTransaction(
            directory: directory, journal: try journal(), steps: steps, failureTitle: "Setup failed")
        await #expect(
            throws: JerdError.partialChange(
                "Setup failed and needs recovery. The helper retained its backup. apply b failed note")
        ) {
            try await transaction.run()
        }
        #expect(try phase(directory) == "b needs recovery. Rolled back: a.")
    }

    /// Regression test: the registration undo writes the exact earlier bytes, not a re-encoded record.
    @Test func registrationUndoRestoresTheExactEarlierBytes() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let directory = RootRecordDirectory(url: folder.path("helper"), owner: getuid())
        let legacy = try Fixture.data("Records/registration-v1.json")
        try directory.write(legacy, to: .registration)
        let plan = SetupPlan(
            directory: directory, hosts: GuardedFileSwap(url: folder.path("hosts"), expectedOwner: getuid()),
            trust: FakeTrust(), before: Data(), after: Data())
        let write = plan.writeRegistrationStep(try Fixture.data("Records/registration-v3.json"), previousBytes: legacy)
        try await write.apply()
        try await write.undo()
        #expect(try directory.read(.registration) == legacy)
        let removal = plan.removeRegistrationStep(previousBytes: legacy)
        try await removal.apply()
        #expect(!directory.exists(.registration))
        try await removal.undo()
        #expect(try directory.read(.registration) == legacy)
    }
}
