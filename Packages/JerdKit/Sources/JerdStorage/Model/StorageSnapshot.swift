import Darwin
import JerdServiceKit

/// The settings, the service state, and the bucket names that RustFS listed, for the Storage page.
public struct StorageSnapshot: Equatable, Sendable {
    public let settings: StorageSettings
    public let state: ServiceState
    /// The names that the running service listed. Empty unless the state is `running`.
    public let availableBuckets: Set<String>

    public init(settings: StorageSettings, state: ServiceState, availableBuckets: Set<String>) {
        self.settings = settings
        self.state = state
        if case .running = state {
            self.availableBuckets = availableBuckets
        } else {
            self.availableBuckets = []
        }
    }

    /// The PID of the owned RustFS process, also while it is stuck.
    public var processID: pid_t? { state.processID }

    /// The row status of `bucket`.
    public func status(of bucket: StorageBucket) -> BucketStatus {
        BucketStatus(bucket: bucket, state: state, listed: availableBuckets)
    }
}
