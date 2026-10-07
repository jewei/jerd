import Foundation
import JerdFoundation
import JerdUI

/// An updater without Sparkle. Tests send events through `send`.
@MainActor
public final class InMemoryUpdater: AppUpdating {
    public var initialState: AppUpdaterState
    /// When set, `start` throws this message, like an invalid feed configuration.
    public var startFailure: String?
    public private(set) var startCount = 0
    public private(set) var checkCount = 0
    public private(set) var automaticCheckRequests: [Bool] = []
    private var events: (@MainActor (AppUpdateEvent) -> Void)?

    public init(
        initialState: AppUpdaterState = AppUpdaterState(canCheck: true, automaticallyChecks: false, lastCheck: nil),
        startFailure: String? = nil
    ) {
        self.initialState = initialState
        self.startFailure = startFailure
    }

    public func start(events: @escaping @MainActor (AppUpdateEvent) -> Void) throws -> AppUpdaterState {
        startCount += 1
        if let startFailure { throw JerdError.invalid(startFailure) }
        self.events = events
        return initialState
    }

    public func checkForUpdates() { checkCount += 1 }

    public func setAutomaticChecks(_ isEnabled: Bool) -> Bool {
        automaticCheckRequests.append(isEnabled)
        return isEnabled
    }

    /// Delivers an event as Sparkle would.
    public func send(_ event: AppUpdateEvent) {
        events?(event)
    }
}
