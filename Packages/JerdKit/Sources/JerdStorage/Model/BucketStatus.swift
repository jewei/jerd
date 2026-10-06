import JerdServiceKit

/// What the Storage page shows for one registered bucket.
///
/// A complete bucket that RustFS does not list is `missing`. Jerd reports it and never creates
/// it again by itself.
public enum BucketStatus: Equatable, Sendable {
    /// The saved intent is not verified yet. Retry finishes it.
    case setupIncomplete
    /// Storage is not running, so the bucket cannot be checked.
    case serviceNotRunning(ServiceState)
    /// RustFS lists the bucket.
    case ready
    /// The bucket is complete, but RustFS does not list it.
    case missing

    /// The status of `bucket` from the service state and the bucket names that RustFS listed.
    public init(bucket: StorageBucket, state: ServiceState, listed: Set<String>) {
        if !bucket.setupComplete {
            self = .setupIncomplete
        } else if case .running = state {
            self = listed.contains(bucket.name) ? .ready : .missing
        } else {
            self = .serviceNotRunning(state)
        }
    }

    /// The short label for the bucket row.
    public var title: String {
        switch self {
        case .setupIncomplete: "Setup incomplete"
        case .ready: "Ready"
        case .missing: "Bucket missing"
        case .serviceNotRunning(let state):
            switch state {
            case .starting: "Storage starting"
            case .stopping: "Storage stopping"
            case .failed, .stuck: "Storage failed"
            case .stopped, .running: "Storage stopped"
            }
        }
    }

    /// True when the row needs the user's attention.
    public var needsAttention: Bool { self == .setupIncomplete || self == .missing }
}
