import Foundation

/// Every effect that the UI needs, as ports. JerdLive builds the live value; JerdUIFixtures
/// builds an in-memory value. A feature work package adds its port here and builds its model
/// in `AppState.init`.
@MainActor
public struct AppDependencies {
    public var info: AppInfo
    /// The `dev.jerd.app` defaults domain.
    public var defaults: UserDefaults
    public var presence: any AppPresenceApplying
    public var iconImages: any AppIconImageProviding
    public var updater: any AppUpdating
    public var runtimes: any RuntimeInventory
    public var recovery: any RecoveryPort
    public var executables: any ExecutableRegistrationPort
    public var httpsRecovery: any HTTPSRecoveryPort
    public var windows: any WindowPresenting
    public var pasteboard: any PasteboardWriting
    public var workspace: any WorkspaceOpening
    public var filePanels: any FilePanelPresenting
    public var sleeper: any Sleeping

    public init(
        info: AppInfo, defaults: UserDefaults, presence: any AppPresenceApplying,
        iconImages: any AppIconImageProviding, updater: any AppUpdating, runtimes: any RuntimeInventory,
        recovery: any RecoveryPort, executables: any ExecutableRegistrationPort, httpsRecovery: any HTTPSRecoveryPort,
        windows: any WindowPresenting, pasteboard: any PasteboardWriting, workspace: any WorkspaceOpening,
        filePanels: any FilePanelPresenting, sleeper: any Sleeping
    ) {
        self.info = info
        self.defaults = defaults
        self.presence = presence
        self.iconImages = iconImages
        self.updater = updater
        self.runtimes = runtimes
        self.recovery = recovery
        self.executables = executables
        self.httpsRecovery = httpsRecovery
        self.windows = windows
        self.pasteboard = pasteboard
        self.workspace = workspace
        self.filePanels = filePanels
        self.sleeper = sleeper
    }
}
