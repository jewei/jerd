/// Runs named steps in order and ends with one summary. It keeps going after a failed step, so one run
/// shows every problem; the exit status is the most severe result.
struct StepSequence {
    struct Record: Equatable {
        var title: String
        var status: ExitStatus
        var duration: Duration
    }

    private(set) var records: [Record] = []
    let console: Console

    init(console: Console) {
        self.console = console
    }

    var exitStatus: ExitStatus {
        records.reduce(.success) { $0.combined(with: $1.status) }
    }

    mutating func run(_ title: String, _ body: () async throws -> Void) async {
        console.step(title)
        let clock = ContinuousClock()
        let start = clock.now
        let status: ExitStatus
        do {
            try await body()
            status = .success
        } catch {
            status = report(error)
        }
        records.append(Record(title: title, status: status, duration: start.duration(to: clock.now)))
    }

    /// Runs one step with the same output and error handling as a longer sequence.
    static func runSingle(_ title: String, console: Console, _ body: () async throws -> Void) async throws {
        var sequence = StepSequence(console: console)
        await sequence.run(title, body)
        try sequence.finish()
    }

    /// Prints the summary when there was more than one step, and throws when a step failed.
    func finish() throws {
        if records.count > 1 {
            printSummary()
        }
        let failed = records.filter { $0.status != .success }
        guard failed.isEmpty else {
            throw DevFailure(status: exitStatus, message: Self.failureMessage(failed: failed, total: records.count))
        }
    }

    static func failureMessage(failed: [Record], total: Int) -> String {
        let titles = failed.map(\.title).joined(separator: ", ")
        if total == 1 {
            return "\(titles) failed."
        }
        return "\(failed.count) of \(total) steps failed: \(titles)."
    }

    private func report(_ error: any Error) -> ExitStatus {
        switch error {
        case let failure as DevFailure:
            console.error(failure.message)
            return failure.status
        case let failure as InvocationFailure:
            console.error(failure.description)
            return .checkFailed
        default:
            console.error(String(describing: error))
            return .checkFailed
        }
    }

    private func printSummary() {
        console.step("Summary")
        let width = records.map(\.title.count).max() ?? 0
        for record in records {
            let label = Self.label(for: record.status).padding(toLength: 8, withPad: " ", startingAt: 0)
            let title = record.title.padding(toLength: width, withPad: " ", startingAt: 0)
            console.detail("\(label) \(title)  \(Self.seconds(record.duration))")
        }
    }

    static func label(for status: ExitStatus) -> String {
        switch status {
        case .success: "ok"
        case .checkFailed: "failed"
        case .usage: "usage"
        case .missingPrerequisite: "missing"
        }
    }

    static func seconds(_ duration: Duration) -> String {
        let tenths = duration.components.seconds * 10 + duration.components.attoseconds / 100_000_000_000_000_000
        return "\(tenths / 10).\(tenths % 10) s"
    }
}
