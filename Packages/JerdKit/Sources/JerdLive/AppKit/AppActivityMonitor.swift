import AppKit
import JerdUI

/// Tells `AppState` when Jerd becomes active or inactive and when its main window becomes
/// visible or hidden (minimized, covered, or the app hidden). The pollers use the fast visible
/// rates only while the user can see live state.
@MainActor
public final class AppActivityMonitor: NSObject {
    /// One change that a notification reports.
    package enum Change: Equatable, Sendable {
        case appActive(Bool)
        case windowVisible(Bool)
    }

    private weak var state: AppState?
    private let center: NotificationCenter

    /// - Parameter center: The center that AppKit posts to; tests pass their own.
    package init(state: AppState, center: NotificationCenter) {
        self.state = state
        self.center = center
        super.init()
    }

    /// Starts to listen, and applies the current activity of the app once.
    package func start(isAppActive: Bool) {
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
            NSWindow.didChangeOcclusionStateNotification,
        ]
        for name in names {
            center.addObserver(self, selector: #selector(received(_:)), name: name, object: nil)
        }
        state?.setAppActive(isAppActive)
    }

    /// AppKit posts these notifications on the main thread.
    @objc private nonisolated func received(_ notification: Notification) {
        let name = notification.name
        let window = notification.object as? NSWindow
        MainActor.assumeIsolated {
            let isVisible = window.map { $0.occlusionState.contains(.visible) } ?? false
            guard
                let change = Self.change(
                    for: name, windowIdentifier: window?.identifier?.rawValue, isWindowVisible: isVisible)
            else { return }
            apply(change)
        }
    }

    /// Maps a notification to a change. Only the main window counts: a sheet, a panel, or the
    /// menu bar window says nothing about whether the user sees the main window.
    package nonisolated static func change(
        for name: Notification.Name, windowIdentifier: String?, isWindowVisible: Bool
    ) -> Change? {
        switch name {
        case NSApplication.didBecomeActiveNotification: return .appActive(true)
        case NSApplication.didResignActiveNotification: return .appActive(false)
        case NSWindow.didChangeOcclusionStateNotification:
            guard MainWindowPresenter.isMainWindow(identifier: windowIdentifier) else { return nil }
            return .windowVisible(isWindowVisible)
        default: return nil
        }
    }

    private func apply(_ change: Change) {
        switch change {
        case .appActive(let isActive): state?.setAppActive(isActive)
        case .windowVisible(let isVisible): state?.setWindowVisible(isVisible)
        }
    }
}
