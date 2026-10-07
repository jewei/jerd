import Foundation

/// The live processes of one update case. The test app records `pid:<number>` at each launch; a PID
/// counts only while its executable is still the installed test app of this case, because the
/// system can reuse a PID for an unrelated process.
struct FixtureProcesses: Sendable {
    let executable: URL
    let inspector: any ProcessInspecting

    /// Every PID that the events name, in order, without duplicates.
    static func recordedPIDs(in events: String) -> [Int32] {
        var seen: Set<Int32> = []
        return events.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("pid:"), let pid = Int32(line.dropFirst(4)), pid > 0, seen.insert(pid).inserted
            else { return nil }
            return pid
        }
    }

    /// The recorded PIDs whose executable is this case's test app.
    func owned(events: String) -> [Int32] {
        let expected = executable.standardizedFileURL.resolvingSymlinksInPath().path
        return Self.recordedPIDs(in: events).filter { pid in
            guard let path = inspector.executablePath(of: pid) else { return false }
            return URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path == expected
        }
    }

    /// Sends SIGTERM to each owned process and waits up to `limit` until none is left.
    /// - Throws: `checkFailed` when an owned process is still running after the limit.
    func stopOwned(events: String, clock: any HarnessClock, limit: Duration = .seconds(5)) async throws {
        for pid in owned(events: events) {
            _ = inspector.terminate(pid)
        }
        let stopped = try await clock.wait(upTo: limit) { owned(events: events).isEmpty }
        guard stopped else {
            throw DevFailure.checkFailed("The test app \(executable.path) did not stop. Stop it, then run again.")
        }
    }
}
