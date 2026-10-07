import AppKit
import JerdDesign
import SwiftUI

/// Keeps a SwiftUI view alive in an offscreen window, so a test can change its state and let
/// it update. `settle()` suspends between layout passes, so `onChange` and `.task` run.
@MainActor
final class ViewHost<Content: View> {
    private let window: NSWindow
    private let hostingView: NSHostingView<Content>

    init(_ content: Content, size: CGSize = CGSize(width: 400, height: 200)) {
        _ = NSApplication.shared
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        hostingView = NSHostingView(rootView: content)
        window.contentView = hostingView
    }

    func settle(passes: Int = 5) async {
        for _ in 0..<passes {
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func close() {
        window.close()
    }
}

/// Records announcements instead of speaking them.
@MainActor
final class RecordingAnnouncer {
    private(set) var announcements: [String] = []

    var announcer: MessageAnnouncer {
        MessageAnnouncer { [weak self] text in self?.announcements.append(text) }
    }
}
