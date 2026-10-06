import Foundation

/// Runs one manual harness and always writes its evidence record, also when the harness stops early.
struct HarnessRun {
    let check: String
    let identity: String
    let context: DevContext
    let clock: any HarnessClock

    /// Runs `body`, which appends one result per case, then writes the record and prints its path.
    /// - Throws: the error of `body`, or `checkFailed` when a case failed.
    func run(_ body: (inout [EvidenceRecord.CaseResult]) async throws -> Void) async throws {
        let date = clock.now()
        let facts = await SystemFacts.read(context)
        var cases: [EvidenceRecord.CaseResult] = []
        var failure: (any Error)?
        do {
            try await body(&cases)
        } catch {
            failure = error
        }
        let record = EvidenceRecord(
            check: check, date: date, identity: identity, facts: facts,
            message: failure.map(Self.message(of:)), cases: cases)
        let file = try write(record, date: date)
        for result in cases {
            let line = "\(result.name): \(result.detail)"
            result.passed ? context.console.success(line) : context.console.error(line)
        }
        context.console.detail("Evidence: \(context.repository.relativePath(of: file))")
        if let failure { throw failure }
        guard record.passed else {
            throw DevFailure.checkFailed("The \(check) check failed. See the evidence record.")
        }
    }

    private func write(_ record: EvidenceRecord, date: Date) throws -> URL {
        let folder = context.repository.evidence
        let file = folder.appending(path: EvidenceRecord.fileName(check: check, date: date))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try record.encoded().write(to: file, options: .withoutOverwriting)
        } catch {
            throw DevFailure.checkFailed("Cannot write the evidence record \(file.path): \(error.localizedDescription)")
        }
        return file
    }

    static func message(of error: any Error) -> String {
        switch error {
        case let failure as DevFailure: failure.message
        case let failure as InvocationFailure: failure.description
        default: String(describing: error)
        }
    }
}
