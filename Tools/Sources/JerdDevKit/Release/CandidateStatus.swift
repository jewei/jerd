import Foundation

/// `./dev release status`: the stage of a candidate, its history, and the next action.
enum CandidateStatus {
    static func lines(_ state: ReleaseState, manifest: ReleaseManifest?) -> [String] {
        var lines: [String] = []
        if let manifest {
            lines.append("Release \(manifest.version) (\(manifest.build)) from \(manifest.sourceCommit.prefix(12)).")
        }
        lines.append("Stage: \(state.stage.rawValue)\(state.stage.isTerminal ? " (final)" : "").")
        if let failure = state.failure {
            lines.append("Failure: \(failure)")
        }
        if let number = state.feedPullRequest {
            lines.append("Feed pull request: #\(number).")
        }
        let formatter = ISO8601DateFormatter()
        for event in state.history {
            lines.append(
                "  \(formatter.string(from: event.date))  \(event.stage.rawValue)\(event.note.map { " – \($0)" } ?? "")"
            )
        }
        lines.append("Next: \(state.stage.nextAction)")
        return lines
    }
}
