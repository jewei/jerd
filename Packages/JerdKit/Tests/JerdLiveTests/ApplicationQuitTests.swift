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

@Suite("Quit Apple Event", .serialized)
@MainActor
struct QuitAppleEventTests {
    /// Sends the quit Apple Event to this process through the event manager, as the Dock and
    /// logout do, and returns the result code of the dispatch.
    static func dispatchQuitEvent(reply: NSAppleEventDescriptor = .null()) -> OSErr {
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEQuitApplication),
            targetDescriptor: .currentProcess(), returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        guard let eventDescription = event.aeDesc, let replyDescription = reply.aeDesc else { return OSErr(paramErr) }
        let mutableReply = UnsafeMutablePointer(mutating: replyDescription)
        let unusedReference = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
        defer { unusedReference.deallocate() }
        return NSAppleEventManager.shared().dispatchRawAppleEvent(
            eventDescription, withRawReply: mutableReply, handlerRefCon: unusedReference)
    }

    /// AppKit's own quit handler calls `terminate(_:)`, which a sheet blocks, so the Dock Quit
    /// and logout must reach the quit that ends the sheets first.
    @Test func theDockAndLogoutQuitEventRunsTheQuitThatEndsTheSheets() {
        var requests = 0
        let handler = QuitAppleEventHandler(manager: .shared()) { requests += 1 }
        handler.install()
        defer { handler.remove() }

        let result = Self.dispatchQuitEvent()

        #expect(result == noErr)
        #expect(requests == 1)
    }

    /// A reply like the one that the event manager makes for a sender that waits.
    static func answer() -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEAnswer), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    }

    /// The quit returns only when Jerd stays open, for example after a shutdown timeout. The
    /// sender (loginwindow at logout) must then get userCanceledErr, as from AppKit's handler.
    @Test func aQuitThatJerdCancelsRepliesUserCanceled() {
        let handler = QuitAppleEventHandler(manager: .shared()) {}
        handler.install()
        defer { handler.remove() }
        let reply = Self.answer()

        let result = Self.dispatchQuitEvent(reply: reply)

        #expect(result == noErr)
        #expect(reply.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value == Int32(userCanceledErr))
    }

    @Test func aSenderThatWaitsForNoReplyGetsNone() {
        let reply = NSAppleEventDescriptor.null()
        QuitAppleEventHandler.reportCancelled(in: reply)
        #expect(reply.descriptorType == typeNull)
    }

    @Test func aRemovedHandlerNoLongerRunsTheQuit() {
        var requests = 0
        let handler = QuitAppleEventHandler(manager: .shared()) { requests += 1 }
        handler.install()
        handler.remove()

        _ = Self.dispatchQuitEvent()

        #expect(requests == 0)
    }
}
