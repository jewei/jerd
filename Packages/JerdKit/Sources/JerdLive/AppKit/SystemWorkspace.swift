import AppKit
import JerdUI

/// Opens addresses and files with their default apps, and shows files in Finder.
@MainActor
public final class SystemWorkspace: WorkspaceOpening {
    private let workspace: NSWorkspace

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    public func open(_ url: URL) {
        workspace.open(url)
    }

    public func reveal(_ url: URL) {
        workspace.activateFileViewerSelecting([url])
    }
}
