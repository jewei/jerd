import Foundation

/// `state.json` of a candidate: the current stage, every change with its time, and the facts that
/// later stages need (the feed pull request). Only `advance` changes the stage, and only along
/// `ReleaseStage.successors`.
struct ReleaseState: Codable, Equatable, Sendable {
    /// One completed stage.
    struct Event: Codable, Equatable, Sendable {
        var stage: ReleaseStage
        var date: Date
        var note: String?
    }

    static let fileName = "state.json"
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    private(set) var stage: ReleaseStage
    private(set) var history: [Event]
    /// The number of the pull request that proposes the feed.
    var feedPullRequest: Int?
    /// Why preparation failed, for `prepareFailed`.
    var failure: String?

    init(startedAt date: Date) {
        stage = .preparing
        history = [Event(stage: .preparing, date: date, note: nil)]
    }

    /// Moves to `next`. A move that the state machine does not allow is a programming or data error.
    mutating func advance(to next: ReleaseStage, at date: Date, note: String? = nil) throws {
        guard stage.successors.contains(next) else {
            throw DevFailure.checkFailed("The candidate cannot move from \(stage.rawValue) to \(next.rawValue).")
        }
        stage = next
        history.append(Event(stage: next, date: date, note: note))
    }

    /// When the candidate was started.
    var startedAt: Date { history.first?.date ?? .distantPast }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self) + Data("\n".utf8)
    }

    static func decode(_ data: Data) throws -> ReleaseState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state: ReleaseState
        do {
            state = try decoder.decode(ReleaseState.self, from: data)
        } catch {
            throw DevFailure.checkFailed("state.json cannot be read. It was preserved. \(error.localizedDescription)")
        }
        guard state.schemaVersion == currentSchemaVersion, state.history.last?.stage == state.stage else {
            throw DevFailure.checkFailed("state.json has an unknown form. It was preserved.")
        }
        return state
    }
}
