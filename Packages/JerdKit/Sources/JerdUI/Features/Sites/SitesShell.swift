/// The window services that the Sites feature uses: navigation, bringing the window forward,
/// and the window alert. Each model takes it as an init argument, so the models never hold the
/// app state and never run without navigation.
@MainActor
public struct SitesShell {
    /// Shows a destination in the window without bringing the window forward.
    public let show: (Destination) -> Void
    /// Shows a destination and brings the window forward, for menu bar commands.
    public let open: (Destination) -> Void
    /// Shows the window alert. Only a failed system setup uses it.
    public let alert: (AppAlert) -> Void

    public init(
        show: @escaping (Destination) -> Void, open: @escaping (Destination) -> Void,
        alert: @escaping (AppAlert) -> Void
    ) {
        self.show = show
        self.open = open
        self.alert = alert
    }
}
