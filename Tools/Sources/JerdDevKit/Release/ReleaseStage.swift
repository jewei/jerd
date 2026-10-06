/// The stages of one release candidate, in order. `state.json` records the last completed stage.
///
/// Preparation ends in `prepared` or in the terminal `prepareFailed`. Publication moves from
/// `prepared` to the terminal `published`; every step between them can run again with
/// `./dev release resume`.
enum ReleaseStage: String, Codable, CaseIterable, Sendable {
    /// `./dev release prepare` is running, or it stopped without a result (for example after a crash).
    case preparing
    /// Terminal: preparation failed. Prepare a new candidate.
    case prepareFailed
    /// The candidate is complete and valid. Nothing is public.
    case prepared
    /// Publication checks passed: the source is on `main`, and no tag or release has the version.
    case checked
    /// A draft release with both assets exists. It is private.
    case draftCreated
    /// The uploaded assets have the candidate digests.
    case assetsVerified
    /// The release and its tag are public. The feed still offers nothing.
    case releasePublic
    /// A pull request proposes the signed feed for `main`.
    case feedProposed
    /// The feed pull request is merged.
    case feedMerged
    /// Terminal: the public feed URL serves the signed candidate feed.
    case published

    var isTerminal: Bool { self == .prepareFailed || self == .published }

    /// The publication changed something on GitHub, so the candidate must stay until it is published.
    var hasPublicationInProgress: Bool {
        switch self {
        case .draftCreated, .assetsVerified, .releasePublic, .feedProposed, .feedMerged: true
        default: false
        }
    }

    /// The stages that may follow this one.
    var successors: Set<ReleaseStage> {
        switch self {
        case .preparing: [.prepared, .prepareFailed]
        case .prepared: [.checked]
        case .checked: [.draftCreated]
        case .draftCreated: [.assetsVerified]
        case .assetsVerified: [.releasePublic]
        case .releasePublic: [.feedProposed]
        case .feedProposed: [.feedMerged]
        case .feedMerged: [.published]
        case .prepareFailed, .published: []
        }
    }

    /// What the user does next.
    var nextAction: String {
        switch self {
        case .preparing: "Wait for ./dev release prepare to finish. If it is not running, prepare a new candidate."
        case .prepareFailed: "Read the logs in the candidate folder, fix the cause, and prepare a new candidate."
        case .prepared: "Run ./dev release publish with this folder."
        case .published: "Nothing. Test the update from an older installed build."
        case .feedProposed: "Merge the feed pull request, then run ./dev release resume with this folder."
        default: "Run ./dev release resume with this folder."
        }
    }
}
