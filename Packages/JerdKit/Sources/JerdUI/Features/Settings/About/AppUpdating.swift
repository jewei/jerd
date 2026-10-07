/// The app updater. The app target implements it with Sparkle: the feed URL and key come from
/// the signed bundle, automatic checks start off, and automatic installation stays off.
/// Its `mayPerform` must throw `AppUpdatesModel.stoppingMessage` while
/// `AppUpdatesModel.allowsUpdateChecks` is false.
@MainActor
public protocol AppUpdating: AnyObject {
    /// Starts the updater once. Throws when the bundle has an invalid feed URL or key; the
    /// updater then never starts.
    func start(events: @escaping @MainActor (AppUpdateEvent) -> Void) throws -> AppUpdaterState
    /// Starts a user-initiated check with the Sparkle user interface.
    func checkForUpdates()
    /// Changes the automatic check preference and returns the value that Sparkle keeps.
    func setAutomaticChecks(_ isEnabled: Bool) -> Bool
}
