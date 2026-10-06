import Foundation

/// Submits a file to Apple's notary service, keeps the results, and staples the ticket.
///
/// The JSON result is read from standard output only, also when `notarytool` exits with a non-zero
/// status for an `Invalid` result. Then the issues log is fetched before the release stops, so the
/// reason is always kept (fixes spec G 8.1 #3).
struct Notarizer: Sendable {
    let shell: ReleaseShell
    let credentials: NotaryCredentials
    let layout: CandidateLayout

    /// - Parameters:
    ///   - file: a zip of the app, or the disk image.
    ///   - name: the prefix of the result files, `app` or `dmg`.
    ///   - staple: the app or the disk image that gets the ticket.
    /// - Returns: the submission ID.
    func notarize(_ file: URL, name: String, staple: URL) async throws -> String {
        shell.console.detail("Submit \(name) to Apple. This can take several minutes.")
        let arguments =
            ["notarytool", "submit", file.path] + credentials.arguments
            + ["--wait", "--timeout", "45m", "--output-format", "json"]
        let result = try await shell.result(
            shell.context.toolchain.xcrun, arguments, limit: TimeLimit.notarization, log: layout.log("\(name)-notary"))
        guard result.exceededTimeLimit == nil, let outcome = NotaryOutcome.parse(standardOutput: result.standardOutput)
        else {
            throw DevFailure.checkFailed(
                "notarytool \(result.failureSummary) without a result. See \(name)-notary.log in the candidate.")
        }
        try Data(result.standardOutput.utf8).write(to: layout.file("\(name)-notary.json"))
        guard outcome.isAccepted, result.succeeded, let id = outcome.validID else {
            try await fetchIssues(of: outcome, name: name)
            throw DevFailure.checkFailed(
                "Apple did not accept \(name) (\(outcome.status ?? "no status")). See \(name)-notary-issues.json.")
        }
        try await shell.xcrun(["stapler", "staple", staple.path], limit: TimeLimit.assessment)
        return id
    }

    private func fetchIssues(of outcome: NotaryOutcome, name: String) async throws {
        guard let id = outcome.validID else { return }
        let issues = layout.file("\(name)-notary-issues.json")
        _ = try await shell.result(
            shell.context.toolchain.xcrun, ["notarytool", "log", id] + credentials.arguments + [issues.path],
            limit: TimeLimit.gitHub, log: layout.log("\(name)-notary"))
    }
}
