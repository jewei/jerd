import AppKit
import Testing

@testable import JerdLive

@Suite("Application quit")
@MainActor
struct ApplicationQuitTests {
    /// A window with an optional sheet. Ending a sheet records its name.
    final class FakeWindow: SheetHosting {
        let name: String
        var attached: FakeWindow?
        weak var host: FakeWindow?
        let ended: (String) -> Void

        init(_ name: String, ended: @escaping (String) -> Void) {
            self.name = name
            self.ended = ended
        }

        func show(_ sheet: FakeWindow) {
            attached = sheet
            sheet.host = self
        }

        var hostedSheet: (any SheetHosting)? { attached }
        var sheetHost: (any SheetHosting)? { host }

        func endHostedSheet(_ sheet: any SheetHosting) {
            guard let sheet = sheet as? FakeWindow, sheet === attached else { return }
            attached = nil
            sheet.host = nil
            ended(sheet.name)
        }
    }

    /// AppKit drops a quit request while a sheet shows, so Quit ends the sheets first.
    @Test func everySheetEndsInnermostFirstBeforeTheQuit() {
        var ended: [String] = []
        let record: (String) -> Void = { ended.append($0) }
        let window = FakeWindow("main", ended: record)
        let sheet = FakeWindow("approval", ended: record)
        let nested = FakeWindow("panel", ended: record)
        let other = FakeWindow("other", ended: record)
        window.show(sheet)
        sheet.show(nested)

        ApplicationQuit.endSheets(in: [window, other])

        #expect(ended == ["panel", "approval"])
        #expect(window.hostedSheet == nil)
    }

    @Test func aRealWindowWithoutASheetStaysAsItIs() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered,
            defer: true)

        ApplicationQuit.endSheets(in: [window])

        #expect(window.attachedSheet == nil)
    }
}
