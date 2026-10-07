import Foundation

/// Runs one update case in its own folder: two signed test apps, a signed feed on a new loopback
/// server, one launch of version 1, and the judgement of its events. Cleanup always runs: the server
/// stops, owned test processes stop, and the preferences (the domain and its plist file), URL storage,
/// and caches of the random bundle identifier are removed (`UpdateCaseCleanup`).
struct UpdateCaseRun: Sendable {
    /// How long a case may take after version 1 ended until its last event and its last process.
    static let completionLimit: Duration = .seconds(60)

    let context: DevContext
    let plan: UpdateFixturePlan
    let effects: UpdateCheckEffects
    let fixture: UpdateFixture

    /// The files of one case.
    struct Folder: Sendable {
        let root: URL
        var events: URL { root.appending(path: "events.txt") }
        var installedApp: URL { root.appending(path: "installed/\(UpdateTestBundle.appName)") }
        var newApp: URL { root.appending(path: "new/\(UpdateTestBundle.appName)") }
        var archive: URL { root.appending(path: "update.zip") }
        var feed: URL { root.appending(path: "appcast.xml") }
        var processLog: URL { root.appending(path: "process.log") }
        var executable: URL { installedApp.appending(path: "Contents/MacOS/\(UpdateTestBundle.executableName)") }
    }

    /// Runs `testCase` below `workFolder` and returns its result.
    /// - Throws: only when cleanup fails, because a test process that keeps running must stop the run.
    func run(_ testCase: UpdateCase, in workFolder: URL) async throws -> EvidenceRecord.CaseResult {
        let folder = Folder(root: workFolder.appending(path: testCase.rawValue, directoryHint: .isDirectory))
        let bundleIdentifier =
            UpdateCaseCleanup.identifierPrefix
            + UUID().uuidString.lowercased().replacingOccurrences(
                of: "-", with: "")
        let server = effects.makeServer()
        let processes = FixtureProcesses(executable: folder.executable, inspector: effects.inspector)
        let outcome: [String]
        do {
            try FileManager.default.createDirectory(at: folder.root, withIntermediateDirectories: true)
            let base = try await server.start(serving: folder.root)
            try await prepare(testCase, in: folder, base: base, bundleIdentifier: bundleIdentifier)
            outcome = try await launchAndJudge(testCase, in: folder, processes: processes)
        } catch {
            outcome = [HarnessRun.message(of: error)]
        }
        try await cleanUp(server: server, processes: processes, folder: folder, bundleIdentifier: bundleIdentifier)
        let detail = outcome.isEmpty ? "passed" : outcome.joined(separator: " ")
        return EvidenceRecord.CaseResult(name: testCase.rawValue, passed: outcome.isEmpty, detail: detail)
    }

    /// Starts version 1, waits for the end of the case, and returns every broken expectation.
    private func launchAndJudge(
        _ testCase: UpdateCase, in folder: Folder, processes: FixtureProcesses
    ) async throws -> [String] {
        let result = try await context.run(plan.launch(folder.installedApp), output: .capture)
        try Data(FailureLog.text(of: result).utf8).write(to: folder.processLog)
        let completed = try await effects.clock.wait(upTo: Self.completionLimit) {
            let events = Self.events(folder)
            return UpdateCase.isComplete(events) && processes.owned(events: events).isEmpty
        }
        let events = Self.events(folder)
        guard completed else {
            return [
                "The case did not end within \(Self.completionLimit.formattedSeconds). Events: \(Self.oneLine(events))"
            ]
        }
        let failures = testCase.failures(
            events: events, installedVersion: UpdateTestBundle.installedVersion(of: folder.installedApp))
        return failures.isEmpty ? [] : failures + ["Events: \(Self.oneLine(events))"]
    }

    private func cleanUp(
        server: any LoopbackFileServing, processes: FixtureProcesses, folder: Folder, bundleIdentifier: String
    ) async throws {
        await server.stop()
        var failure: (any Error)?
        do {
            try await processes.stopOwned(events: Self.events(folder), clock: effects.clock)
        } catch {
            failure = error
        }
        // Also after a failure: the defaults domain, its plist, and the URL and cache folders go.
        // The domain does not exist when Sparkle wrote nothing, so the status does not matter.
        do {
            _ = try await context.run(plan.deleteDefaults(bundleIdentifier: bundleIdentifier), output: .capture)
        } catch {
            failure = failure ?? error
        }
        do {
            try UpdateCaseCleanup(home: effects.home, bundleIdentifier: bundleIdentifier).removeFiles()
        } catch {
            failure = failure ?? error
        }
        if let failure { throw failure }
    }

    static func events(_ folder: Folder) -> String {
        FileManager.default.contents(atPath: folder.events.path).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    static func oneLine(_ events: String) -> String {
        events.split(separator: "\n").joined(separator: ", ")
    }
}
