/// How often a feature refreshes its state. Visible state refreshes fast; hidden state keeps a
/// slow tick, so a service that stops by itself still shows correctly when the window returns.
public struct PollingPolicy: Equatable, Sendable {
    /// The interval while the user can see live state.
    public let visibleInterval: Duration
    /// The interval while no window or menu shows.
    public let backgroundInterval: Duration

    public init(visibleInterval: Duration, backgroundInterval: Duration) {
        self.visibleInterval = visibleInterval
        self.backgroundInterval = max(visibleInterval, backgroundInterval)
    }

    /// The interval for the given activity.
    public func interval(for activity: AppActivity) -> Duration {
        activity.showsLiveState ? visibleInterval : backgroundInterval
    }

    /// The web environment: PHP-FPM and Caddy.
    public static let environment = PollingPolicy(visibleInterval: .milliseconds(500), backgroundInterval: .seconds(5))
    /// Databases, storage, and mail.
    public static let services = PollingPolicy(visibleInterval: .milliseconds(700), backgroundInterval: .seconds(5))
    /// Cloudflare tunnel connectors.
    public static let tunnels = PollingPolicy(visibleInterval: .seconds(1), backgroundInterval: .seconds(5))
}
