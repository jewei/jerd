import SwiftUI
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

    @Test("A header status always names its subject")
    func headerStatusNamesSubject() throws {
        let header = PageHeader("Mail", status: NamedStatus("Mail status", DisplayStatus("Ready", tone: .ready)))
        let status = try #require(header.status)
        #expect(status.subject == "Mail status")
        #expect(status.spokenDescription == "Mail status, Ready")
    }

    @Test("Page, sheet, and card titles are headers; body text is not")
    func titlesAreHeaders() {
        let headers = TextRole.allCases.filter(\.isHeader)
        #expect(headers == [.pageTitle, .sheetTitle, .cardTitle])
    }

    @Test("Only detail, caption, and path text use the secondary color")
    func secondaryRoles() {
        #expect(TextRole.allCases.filter(\.isSecondary) == [.detail, .caption, .path])
    }

    @Test("Every path uses one monospaced detail style")
    func pathStyle() {
        #expect(TextRole.path.font == Font.callout.monospaced())
    }

    @Test("Return confirms a sheet only when the action cannot destroy data")
    func returnKeyIsNotDestructive() {
        #expect(SheetConfirmation("Save") {}.usesReturnKey)
        #expect(!SheetConfirmation("Delete Backup", isDestructive: true) {}.usesReturnKey)
    }

    @Test("The confirm button is disabled while the sheet works")
    func confirmWaitsForWork() {
        #expect(sheet(isEnabled: true, workingMessage: nil).isConfirmEnabled)
        #expect(!sheet(isEnabled: true, workingMessage: "Checking…").isConfirmEnabled)
        #expect(!sheet(isEnabled: false, workingMessage: nil).isConfirmEnabled)
    }

    private func sheet(isEnabled: Bool, workingMessage: String?) -> SheetScaffold<EmptyView> {
        let confirmation = SheetConfirmation("Save", isEnabled: isEnabled, perform: {})
        return SheetScaffold(
            "Edit Site", confirmation: confirmation, workingMessage: workingMessage, cancel: {},
            content: { EmptyView() })
    }

    @Test("Page actions are not identified by their title, so two actions may share one")
    func pageActionsAreNotIdentifiedByTitle() {
        let action = PageAction("Open") {}
        #expect(!(action as Any is any Identifiable))
    }
}
