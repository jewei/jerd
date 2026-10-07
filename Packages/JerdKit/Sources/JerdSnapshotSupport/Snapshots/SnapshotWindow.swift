import AppKit
import JerdDesign

/// Makes the offscreen window for a snapshot. The window is never ordered on screen.
@MainActor
enum SnapshotWindow {
    static func make(size: CGSize, chrome: SnapshotChrome, appearance: NSAppearance?) -> NSWindow {
        let frame = NSRect(origin: .zero, size: size)
        let window: NSWindow
        switch chrome {
        case .content:
            window = ActiveWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        case .window(let title):
            window = ActiveWindow(
                contentRect: frame,
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = title
            window.toolbarStyle = .unified
            // Like the app's window from macOS 26: the toolbar floats over the content, and the
            // sidebar and the page reach under it. Offscreen, the toolbar would draw an opaque
            // bar with a hard line instead.
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.setFrame(frame, display: false)
        }
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.appearance = appearance
        return window
    }
}
