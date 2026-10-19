import AppKit
import SwiftUI

@testable import JerdUI

/// Two retained pages in a real window: a hidden page that presents a sheet, and the visible
/// page. Tests read what the sheet receives and which text fields the key view loop reaches.
@MainActor
final class RetainedPageHarness {
    /// What the sheet of the hidden page received when it appeared.
    final class SheetReport {
        var isEnabled: Bool?
    }

    static let hiddenField = "Hidden page field"
    static let visibleField = "Visible page field"
    static let sheetField = "Sheet field"

    let report = SheetReport()
    let window: NSWindow

    init() {
        _ = NSApplication.shared
        // AppKit presents sheets and builds the key view loop only for a window on screen, and
        // the test must not show a window to the user. So the window is ordered in, transparent,
        // and outside every screen. AppKit moves a parent back onto a screen to show its sheet,
        // so the position alone does not hide it.
        window = UnconstrainedWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 480, height: 320), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.alphaValue = 0
        let pages = ZStack {
            ProbePage(field: Self.hiddenField, presentsSheet: true, report: report)
                .retainedPage(isVisible: false)
            ProbePage(field: Self.visibleField, presentsSheet: false, report: report)
                .retainedPage(isVisible: true)
        }
        .frame(width: 480, height: 320)
        window.contentView = NSHostingView(rootView: pages)
        window.orderFrontRegardless()
    }

    /// Runs the main run loop until `condition` is true, or for about two seconds.
    func run(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    /// The text fields that Tab reaches in `window`, by placeholder.
    func keyViewFields(in window: NSWindow, steps: Int = 6) -> [String] {
        window.makeFirstResponder(nil)
        var fields: [String] = []
        for _ in 0..<steps {
            window.selectNextKeyView(nil)
            if let editor = window.firstResponder as? NSTextView, let field = editor.delegate as? NSTextField {
                fields.append(field.placeholderString ?? "")
            } else if let field = window.firstResponder as? NSTextField {
                fields.append(field.placeholderString ?? "")
            }
        }
        return fields
    }

    func close() {
        for sheet in window.sheets {
            window.endSheet(sheet)
        }
        window.close()
    }
}

/// A page with one text field. It presents its sheet once it appears, if asked.
private struct ProbePage: View {
    let field: String
    let presentsSheet: Bool
    let report: RetainedPageHarness.SheetReport
    @State private var isPresented = false

    var body: some View {
        VStack {
            TextField(field, text: .constant(""))
        }
        .padding()
        .sheet(isPresented: $isPresented) {
            ProbeSheet(report: report)
        }
        .onAppear {
            if presentsSheet { isPresented = true }
        }
    }
}

private struct ProbeSheet: View {
    let report: RetainedPageHarness.SheetReport
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack {
            TextField(RetainedPageHarness.sheetField, text: .constant(""))
            Button("Cancel") {}
        }
        .frame(width: 240, height: 120)
        .background(TransparentSheetWindow())
        .onAppear { report.isEnabled = isEnabled }
    }
}

/// Makes the sheet window transparent before it is shown. AppKit places a sheet on a screen even
/// when its parent is outside every screen, and the test must not show it to the user.
private struct TransparentSheetWindow: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.alphaValue = 0
        }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ nsView: Probe, context: Context) {}
}

/// A window that keeps the frame it is given. AppKit moves a titled window back onto a screen
/// when it is ordered in; the harness must stay outside every screen.
private final class UnconstrainedWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
