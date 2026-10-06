import Foundation

/// Decides which old candidates `./dev release clean` removes. Pure.
///
/// It keeps the newest `keep` candidates. It never removes a candidate whose publication changed
/// GitHub and is not finished, because `resume` needs its files, and never one that is still being
/// prepared. A candidate without a readable state is kept too: it may be from an older tool.
enum CandidateSelection {
    struct Candidate: Equatable, Sendable {
        var name: String
        var startedAt: Date
        /// Nil when `state.json` is missing or cannot be read.
        var stage: ReleaseStage?
    }

    struct Result: Equatable, Sendable {
        var remove: [String] = []
        /// Old candidates that stay, with the reason.
        var protected: [(name: String, reason: String)] = []

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.remove == rhs.remove && lhs.protected.map(\.name) == rhs.protected.map(\.name)
        }
    }

    static func select(_ candidates: [Candidate], keep: Int) -> Result {
        let sorted = candidates.sorted { ($0.startedAt, $0.name) > ($1.startedAt, $1.name) }
        var result = Result()
        for candidate in sorted.dropFirst(max(keep, 0)) {
            if let reason = protection(of: candidate) {
                result.protected.append((candidate.name, reason))
            } else {
                result.remove.append(candidate.name)
            }
        }
        return result
    }

    static func protection(of candidate: Candidate) -> String? {
        guard let stage = candidate.stage else { return "it has no readable state.json" }
        if stage.hasPublicationInProgress { return "its publication is at \(stage.rawValue); resume it first" }
        if stage == .preparing { return "it is still being prepared; remove it by hand if no preparation runs" }
        return nil
    }
}
