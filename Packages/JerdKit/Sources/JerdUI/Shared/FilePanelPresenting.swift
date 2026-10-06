import Foundation

/// Shows open panels as sheets on the main window, never as app-modal windows.
/// JerdLive implements it with `NSOpenPanel.beginSheetModal`.
@MainActor
public protocol FilePanelPresenting: AnyObject {
    /// Returns the selected item, or nil when the user cancels.
    func choose(_ request: FilePanelRequest) async -> URL?
}
