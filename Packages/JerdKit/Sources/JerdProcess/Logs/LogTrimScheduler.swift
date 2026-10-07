import Foundation
import JerdFoundation

/// Trims every registered log once per interval while at least one log is registered.
///
/// A burst of output can exceed the threshold between two passes; the next pass bounds it.
/// A failed trim is kept for inspection instead of being ignored.
actor LogTrimScheduler {
    private let interval: Duration
    private var logs: Set<ProcessLogFile> = []
    private var failures: [URL: String] = [:]
    private var loop: Task<Void, Never>?

    init(interval: Duration = .seconds(1)) { self.interval = interval }

    /// Adds a log and starts the periodic pass if needed.
    func register(_ log: ProcessLogFile) {
        logs.insert(log)
        guard loop == nil else { return }
        let interval = interval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { return }
                await self.trimAll()
            }
        }
    }

    /// Removes a log after one final trim. The periodic pass stops when no log remains.
    /// - Returns: the failure of the final trim (or of an earlier trim that was not fixed), or nil.
    ///   The scheduler then forgets the log, so its failures do not accumulate.
    @discardableResult
    func unregister(_ log: ProcessLogFile) -> String? {
        guard logs.remove(log) != nil else { return nil }
        trim(log)
        if logs.isEmpty {
            loop?.cancel()
            loop = nil
        }
        return failures.removeValue(forKey: log.url)
    }

    /// The message of the last failed trim of `url`, or nil.
    func failure(for url: URL) -> String? { failures[url] }

    /// True while the periodic pass runs.
    var isRunning: Bool { loop != nil }

    private func trimAll() {
        for log in logs { trim(log) }
    }

    private func trim(_ log: ProcessLogFile) {
        do {
            try log.trim()
            failures[log.url] = nil
        } catch {
            failures[log.url] = FailureDetail.describe(error)
        }
    }
}
