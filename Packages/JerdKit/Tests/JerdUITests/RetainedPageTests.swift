import AppKit
import Testing

@testable import JerdUI

@Suite("Retained pages", .serialized)
@MainActor
struct RetainedPageTests {
    @Test("A sheet of a hidden retained page stays enabled and takes keyboard focus")
    func hiddenPageSheetStaysUsable() throws {
        let harness = RetainedPageHarness()
        defer { harness.close() }
        harness.run { harness.report.isEnabled != nil && !harness.window.sheets.isEmpty }
        #expect(harness.report.isEnabled == true)
        let sheet = try #require(harness.window.sheets.first)
        #expect(harness.keyViewFields(in: sheet).contains(RetainedPageHarness.sheetField))
    }

    @Test("Tab never reaches a field of a hidden retained page")
    func hiddenPageTakesNoFocus() {
        let harness = RetainedPageHarness()
        defer { harness.close() }
        harness.run { !harness.window.sheets.isEmpty }
        for sheet in harness.window.sheets {
            harness.window.endSheet(sheet)
        }
        harness.run { harness.window.sheets.isEmpty }
        let fields = harness.keyViewFields(in: harness.window)
        #expect(fields.contains(RetainedPageHarness.visibleField))
        #expect(!fields.contains(RetainedPageHarness.hiddenField))
    }
}
