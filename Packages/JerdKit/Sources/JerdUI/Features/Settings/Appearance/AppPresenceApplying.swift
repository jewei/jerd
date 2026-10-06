/// Applies the Dock and icon choices to the running app. JerdLive implements it with
/// `NSApp.setActivationPolicy` and `NSApp.applicationIconImage`. The menu bar extra follows
/// `AppearanceModel.showMenuBar` through the scene, so it needs no port.
@MainActor
public protocol AppPresenceApplying: AnyObject {
    /// `true` shows the Dock icon (regular app); `false` hides it (accessory app).
    func showInDock(_ isShown: Bool)
    /// Uses the icon for the Dock and the app while Jerd runs.
    func useIcon(_ icon: AppIconChoice)
}
