import Foundation

/// `./dev release publish` and `resume`: the publication state machine of one prepared candidate.
///
/// Each stage is one idempotent step, and `state.json` records each completed stage, so `resume`
/// continues where a failure stopped. The assets become public before the feed. The feed goes to
/// `main` through a pull request, never by a direct push, and publication ends
/// only when the public feed URL serves the signed candidate feed (#8, #10).
struct ReleasePublisher: Sendable {
    /// How a run ended.
    enum Outcome: Equatable, Sendable {
        case published
        /// The feed pull request waits for review and merge.
        case waitingForMerge(Int)
        /// The feed is merged, but the public URL does not serve it yet.
        case feedNotYetPublic
    }

    let environment: ReleaseEnvironment
    let layout: CandidateLayout
    /// How often and how long publication waits for the public feed URL (the raw CDN can lag).
    var feedAttempts = 20
    var feedInterval: Duration = .seconds(30)
    /// The full candidate check before anything changes on GitHub. Tests replace it.
    var validateCandidate: @Sendable (ReleaseEnvironment, CandidateLayout) async throws -> Void = {
        environment, layout in
        try await ReleaseValidator(shell: environment.shell, layout: layout, verifier: environment.verifier)
            .run(publicKeyOnly: true)
    }

    var shell: ReleaseShell { environment.shell }

    /// - Parameter resuming: false for `publish`, which starts only from `prepared`; true for `resume`,
    ///   which continues a started publication.
    func run(resuming: Bool) async throws -> Outcome {
        var state = try CandidateStore.load(layout)
        try Self.requireStart(state.stage, resuming: resuming)
        let manifest = try ReleaseManifest.decode(try Data(contentsOf: layout.manifest))
        try ReleaseValidator.checkFiles(manifest, in: layout.root)
        let facts = try PublicationFacts(manifest: manifest)
        while true {
            guard let next = try await step(state.stage, facts: facts, state: &state) else {
                return try outcome(of: state)
            }
            try state.advance(to: next, at: environment.clock.now())
            try CandidateStore.save(state, to: layout)
            environment.console.success("Stage \(next.rawValue) reached.")
        }
    }

    static func requireStart(_ stage: ReleaseStage, resuming: Bool) throws {
        switch (stage, resuming) {
        case (.prepared, false), (.published, true): return
        case (.prepared, true):
            throw DevFailure.usage("This candidate is not being published. Run ./dev release publish first.")
        case (.preparing, _), (.prepareFailed, _):
            throw DevFailure.checkFailed("This candidate is not prepared (\(stage.rawValue)). \(stage.nextAction)")
        case (.published, false):
            throw DevFailure.checkFailed("This candidate is already published.")
        case (_, false):
            throw DevFailure.usage("Publication has started (\(stage.rawValue)). Run ./dev release resume instead.")
        case (_, true): return
        }
    }

    /// Runs the step after `stage` and returns the stage that it completes, or nil to stop.
    private func step(
        _ stage: ReleaseStage, facts: PublicationFacts, state: inout ReleaseState
    ) async throws
        -> ReleaseStage?
    {
        switch stage {
        case .prepared:
            try await checkPublication(facts)
            return .checked
        case .checked:
            try await createDraft(facts)
            return .draftCreated
        case .draftCreated:
            try await verifyAssets(facts)
            return .assetsVerified
        case .assetsVerified:
            try await makePublic(facts)
            return .releasePublic
        case .releasePublic:
            state.feedPullRequest = try await proposeFeed(facts)
            return .feedProposed
        case .feedProposed:
            guard let number = state.feedPullRequest else {
                throw DevFailure.checkFailed("state.json has no feed pull request.")
            }
            return try await isMerged(number, facts: facts) ? .feedMerged : nil
        case .feedMerged:
            guard try await feedIsPublic() else { return nil }
            await deleteFeedBranch(facts)
            return .published
        case .preparing, .prepareFailed, .published:
            return nil
        }
    }

    private func outcome(of state: ReleaseState) throws -> Outcome {
        switch state.stage {
        case .published: return .published
        case .feedProposed: return .waitingForMerge(state.feedPullRequest ?? 0)
        case .feedMerged: return .feedNotYetPublic
        default: throw DevFailure.checkFailed("Publication stopped at \(state.stage.rawValue).")
        }
    }
}
