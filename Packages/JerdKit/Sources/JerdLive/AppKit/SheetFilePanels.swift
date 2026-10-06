import AppKit
import JerdUI

/// Shows open panels as sheets on the key window, so they never block the app. Without a
/// window it shows a free panel.
@MainActor
public final class SheetFilePanels: FilePanelPresenting {
    public init() {}

    public func choose(_ request: FilePanelRequest) async -> URL? {
        let panel = Self.panel(for: request)
        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = await withCheckedContinuation { continuation in
                panel.begin { continuation.resume(returning: $0) }
            }
        }
        return response == .OK ? panel.url : nil
    }

    /// One item of the requested kind. Links resolve, so the inspector sees the real file.
    package static func panel(for request: FilePanelRequest) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.message = request.message
        panel.prompt = request.prompt
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.canCreateDirectories = false
        switch request.kind {
        case .executable:
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.treatsFilePackagesAsDirectories = true
        case .folder:
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
        }
        return panel
    }
}
