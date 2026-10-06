/// Calls a refresh function on a schedule that follows `PollingPolicy`. When the activity
/// changes to a shorter interval, for example when the window appears, the poller refreshes at
/// once and then continues at the new pace. `stop()` ends polling for good after shutdown.
@MainActor
public final class ServicePoller {
    private let policy: PollingPolicy
    private let sleeper: any Sleeping
    private let refresh: @MainActor () async -> Void
    private var activity = AppActivity()
    private var loop: Task<Void, Never>?
    private var isStopped = false

    public init(policy: PollingPolicy, sleeper: any Sleeping, refresh: @escaping @MainActor () async -> Void) {
        self.policy = policy
        self.sleeper = sleeper
        self.refresh = refresh
    }

    /// True between `start` and `stop`.
    public var isRunning: Bool { loop != nil }

    /// Starts polling. The first refresh comes after one interval. Does nothing after `stop()`.
    public func start(activity: AppActivity) {
        guard !isStopped, loop == nil else { return }
        self.activity = activity
        loop = makeLoop(refreshFirst: false)
    }

    /// Applies a new activity. A shorter interval restarts the loop with an immediate refresh.
    public func update(activity newActivity: AppActivity) {
        let previous = policy.interval(for: activity)
        activity = newActivity
        guard loop != nil, policy.interval(for: newActivity) < previous else { return }
        loop?.cancel()
        loop = makeLoop(refreshFirst: true)
    }

    /// Stops polling for good. A later `start` does nothing.
    public func stop() {
        isStopped = true
        loop?.cancel()
        loop = nil
    }

    /// The loop holds the poller weakly, so a poller that nobody owns ends its loop.
    private func makeLoop(refreshFirst: Bool) -> Task<Void, Never> {
        let sleeper = sleeper
        return Task { [weak self] in
            if refreshFirst {
                await self?.refreshIfCurrent()
            }
            while !Task.isCancelled, let interval = self?.currentInterval {
                do {
                    try await sleeper.sleep(for: interval)
                } catch {
                    return
                }
                await self?.refreshIfCurrent()
            }
        }
    }

    private var currentInterval: Duration {
        policy.interval(for: activity)
    }

    private func refreshIfCurrent() async {
        guard !Task.isCancelled, !isStopped else { return }
        await refresh()
    }
}
