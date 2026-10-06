/// One polling loop of a feature: how often, and what it reads. `AppState` runs one
/// `ServicePoller` per task.
public struct PollingTask {
    public let policy: PollingPolicy
    public let refresh: @MainActor () async -> Void

    public init(policy: PollingPolicy, refresh: @escaping @MainActor () async -> Void) {
        self.policy = policy
        self.refresh = refresh
    }
}
