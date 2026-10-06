import AppKit
import JerdUI

/// Brings the one main window to the front, or opens it when it is closed.
///
/// SwiftUI owns the window, so only a SwiftUI view can open it: the app scene hands over its
/// `openWindow` action with `connect(_:)` as soon as the window or the menu bar item appears.
/// Until then, reopening the app (`applicationShouldHandleReopen`) lets SwiftUI open it.
@MainActor
public final class MainWindowPresenter: WindowPresenting {
    /// The scene ID of the main window.
    public static let windowID = "main"

    private var openWindow: (@MainActor () -> Void)?

    public init() {}

    /// Keeps the action that opens the main window scene.
    public func connect(_ open: @escaping @MainActor () -> Void) {
        openWindow = open
    }

    public func showMainWindow() {
        NSApp.activate()
        if let window = mainWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow?()
        }
    }

    /// The open main window. SwiftUI names a scene window after the scene ID.
    private var mainWindow: NSWindow? {
        NSApp.windows.first { window in
            (window.isVisible || window.isMiniaturized) && Self.isMainWindow(identifier: window.identifier?.rawValue)
        }
    }

    package static func isMainWindow(identifier: String?) -> Bool {
        guard let identifier else { return false }
        return identifier == windowID || identifier.hasPrefix("\(windowID)-")
    }
}
