import Foundation

/// What the updater reports. The Sparkle adapter in the app target sends these events.
public enum AppUpdateEvent: Equatable, Sendable {
    /// Sparkle can or cannot start a check now.
    case canCheckChanged(Bool)
    case automaticChecksChanged(Bool)
    /// A check starts (Sparkle `mayPerform`).
    case checkStarted
    /// A valid update with this display version exists.
    case updateFound(String)
    case noUpdateFound
    /// An update cycle ended, with the last check date that Sparkle keeps.
    case cycleFinished(lastCheck: Date?, result: AppUpdateCycleResult)
}
