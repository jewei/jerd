import Testing

@testable import JerdDesign

@Suite("Component accessibility")
@MainActor
struct ComponentAccessibilityTests {
    @Test("A sidebar row reads its subtitle and status after the title")
    func sidebarRowValue() {
        let row = SidebarRow("Studio", subtitle: "studio.test", status: DisplayStatus("Ready", tone: .ready))
        #expect(row.spokenValue == "studio.test, Ready")
    }

    @Test("A sidebar row without a subtitle reads only its status")
    func sidebarRowValueWithoutSubtitle() {
        let row = SidebarRow("Studio", status: DisplayStatus("Stopped", tone: .idle))
        #expect(row.spokenValue == "Stopped")
    }

    @Test("Page, sheet, and card titles are headers; body text is not")
    func titlesAreHeaders() {
        let headers = TextRole.allCases.filter(\.isHeader)
        #expect(headers == [.pageTitle, .sheetTitle, .cardTitle])
    }

    @Test("Only detail and caption text use the secondary color")
    func secondaryRoles() {
        #expect(TextRole.allCases.filter(\.isSecondary) == [.detail, .caption])
    }

    @Test("Return confirms a sheet only when the action cannot destroy data")
    func returnKeyIsNotDestructive() {
        #expect(SheetConfirmation("Save") {}.usesReturnKey)
        #expect(!SheetConfirmation("Delete Backup", isDestructive: true) {}.usesReturnKey)
    }
}
