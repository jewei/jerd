import Foundation
import JerdUI

/// Records the window, pasteboard, Finder, Dock, and icon effects of the UI, and performs none.
@MainActor
public final class InMemoryShell: AppPresenceApplying, WindowPresenting, PasteboardWriting, WorkspaceOpening {
    public private(set) var windowRequests = 0
    public private(set) var pasteboard: [String] = []
    public private(set) var openedURLs: [URL] = []
    public private(set) var revealedURLs: [URL] = []
    public private(set) var dockStates: [Bool] = []
    public private(set) var icons: [AppIconChoice] = []

    public init() {}

    public func showMainWindow() { windowRequests += 1 }
    public func write(_ text: String) { pasteboard.append(text) }
    public func open(_ url: URL) { openedURLs.append(url) }
    public func reveal(_ url: URL) { revealedURLs.append(url) }
    public func showInDock(_ isShown: Bool) { dockStates.append(isShown) }
    public func useIcon(_ icon: AppIconChoice) { icons.append(icon) }
}
