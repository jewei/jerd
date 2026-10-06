import Foundation

/// Opens URLs and shows files in Finder. JerdLive implements it with `NSWorkspace`.
@MainActor
public protocol WorkspaceOpening: AnyObject {
    /// Opens a web address or a file with its default app.
    func open(_ url: URL)
    /// Selects a file or folder in a Finder window.
    func reveal(_ url: URL)
}
