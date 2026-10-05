import Foundation
import JerdFoundation

/// Runs the steps of one journaled transaction, and undoes the completed steps after a failure.
///
/// Order: write the journal, then for each step write its start phase (if any), apply it, and write
/// its done phase. Then commit: delete the journal. After a failure, the completed steps (and a failed
/// step whose effect may have happened) are undone in reverse order. The journal is deleted only when
/// every undo succeeded and no step asked to keep it; then the original error is thrown. Otherwise the
/// journal stays with a phase that names what was rolled back, and the error is `.partialChange`.
struct SetupTransaction {
    let directory: RootRecordDirectory
    var journal: SetupJournal
    let steps: [SetupStep]
    /// The start of the error message when the journal must stay, for example "Setup failed".
    let failureTitle: String

    mutating func run() async throws {
        try save()
        var completed: [SetupStep] = []
        var notes: [String] = []
        do {
            for step in steps {
                try await perform(step, completed: &completed, notes: &notes)
            }
            try directory.remove(.pending)
        } catch {
            try await compensate(after: error, completed: completed, notes: notes)
        }
    }

    private mutating func perform(_ step: SetupStep, completed: inout [SetupStep], notes: inout [String]) async throws {
        if let start = step.startPhase { try save(phase: start) }
        do {
            try await step.apply()
        } catch {
            let failure = step.classify(error)
            if failure.undo { completed.append(step) }
            if let phase = failure.phase { notes += saveKeepingNote(phase: phase) }
            if let note = failure.retainNote { notes.append(note) }
            throw error
        }
        completed.append(step)
        try save(phase: step.donePhase)
    }

    private mutating func compensate(after error: any Error, completed: [SetupStep], notes: [String]) async throws {
        var notes = notes
        var undone: [String] = []
        var failed: [String] = []
        for step in completed.reversed() {
            do {
                try await step.undo()
                undone.append(step.label)
            } catch {
                failed.append(step.label)
                notes.append(HelperRecordCodec.describe(error))
            }
        }
        if notes.isEmpty {
            do {
                try directory.remove(.pending)
            } catch {
                notes.append("The helper could not remove its recovery record: \(HelperRecordCodec.describe(error))")
            }
            if notes.isEmpty { throw error }
        }
        let summary = Self.summary(undone: undone, failed: failed)
        let base = summary.isEmpty || journal.phase.hasSuffix(".") ? journal.phase : journal.phase + "."
        notes += saveKeepingNote(phase: base + summary)
        let original = HelperRecordCodec.describe(error)
        let details = ([original] + notes.filter { $0 != original }).joined(separator: " ")
        throw JerdError.partialChange("\(failureTitle) and needs recovery. The helper retained its backup. \(details)")
    }

    static func summary(undone: [String], failed: [String]) -> String {
        var parts: [String] = []
        if !undone.isEmpty { parts.append(" Rolled back: \(undone.joined(separator: ", ")).") }
        if !failed.isEmpty { parts.append(" Rollback failed: \(failed.joined(separator: ", ")).") }
        return parts.joined()
    }

    private mutating func save(phase: String? = nil) throws {
        if let phase { journal.phase = phase }
        try directory.write(HelperRecordCodec.encode(journal), to: .pending)
    }

    /// Writes a failure phase. A write failure does not hide the original error; it becomes a note.
    private mutating func saveKeepingNote(phase: String) -> [String] {
        do {
            try save(phase: phase)
            return []
        } catch {
            return ["The helper could not update its recovery record: \(HelperRecordCodec.describe(error))"]
        }
    }
}
