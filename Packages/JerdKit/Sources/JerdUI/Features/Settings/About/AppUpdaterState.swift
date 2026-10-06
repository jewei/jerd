import Foundation

/// The updater values right after it starts.
public struct AppUpdaterState: Equatable, Sendable {
    public let canCheck: Bool
    public let automaticallyChecks: Bool
    public let lastCheck: Date?

    public init(canCheck: Bool, automaticallyChecks: Bool, lastCheck: Date?) {
        self.canCheck = canCheck
        self.automaticallyChecks = automaticallyChecks
        self.lastCheck = lastCheck
    }
}
