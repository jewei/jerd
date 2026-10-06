import AppKit
import JerdDesign
import JerdFoundation
import JerdUI
import SwiftUI

@testable import JerdLive

/// The main window as the app builds it: a titled window with a unified toolbar and a full-size
/// content view, `JerdWorkspace` with the native split, and the SwiftUI toolbar bridged to the
/// window. The window is never ordered on screen.
@MainActor
final class WorkspaceWindow {
    let temporary: TemporaryDirectory
    let live: LiveApp
    let window: NSWindow
    let host: NSHostingView<JerdWorkspace<WorkspaceSplit>>

    var state: AppState { live.state }

    init(width: CGFloat, autosaveName: String? = nil) throws {
        _ = NSApplication.shared
        temporary = try TemporaryDirectory()
        live = LiveApp(
            configuration: try LiveAppTests.configuration(in: temporary), updater: LiveAppTests.SilentUpdater(),
            defaults: try LiveAppTests.defaults())
        let frame = NSRect(x: 0, y: 0, width: width, height: WindowMetrics.standardSize.height)
        window = NSWindow(
            contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.toolbarStyle = .unified
        window.setFrame(frame, display: false)
        let state = live.state
        host = NSHostingView(
            rootView: JerdWorkspace(state: state) { columns in
                WorkspaceSplit(columns: columns, autosaveName: autosaveName)
            })
        host.sceneBridgingOptions = [.toolbars, .title]
        window.contentView = host
        settle()
    }

    /// Closes the window and removes the data folder.
    func close() {
        window.close()
        temporary.remove()
    }

    /// Runs layout and the run loop until SwiftUI and AppKit applied every change.
    func settle(passes: Int = 15) {
        for _ in 0..<passes {
            window.layoutIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// The split controller inside the hosting view.
    var split: WorkspaceSplitController? {
        Self.controller(in: window.contentView)
    }

    /// The section picker: the toolbar's centered item.
    var picker: NSView? { window.toolbar?.centeredItemView }

    /// The sidebar button: the leading visible toolbar item that is not the picker.
    var sidebarButton: NSView? {
        let pickerView = picker
        return (window.toolbar?.items ?? []).compactMap(\.view)
            .filter { $0 !== pickerView && !$0.isHiddenOrHasHiddenAncestor }
            .min { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
    }

    /// A view's frame in window coordinates.
    func frame(of view: NSView?) -> NSRect {
        guard let view else { return .zero }
        return view.convert(view.bounds, to: nil)
    }

    private static func controller(in view: NSView?) -> WorkspaceSplitController? {
        guard let view else { return nil }
        if let controller = view.nextResponder as? WorkspaceSplitController { return controller }
        for subview in view.subviews {
            if let found = controller(in: subview) { return found }
        }
        return nil
    }
}
