import Testing

@testable import JerdDesign

@Suite("Accessibility identifiers")
@MainActor
struct AccessibilityIdentifierTests {
    @Test(
        "A slug keeps lower-case letters and digits and joins other runs with one hyphen",
        arguments: [
            ("Inbox URL", "inbox-url"), ("  PHP 8.5 — FPM!  ", "php-8-5-fpm"), ("site-editor", "site-editor"),
            ("…", ""),
        ])
    func slug(text: String, expected: String) {
        #expect(AccessibilityIdentifier.slug(text) == expected)
    }

    @Test("Identifier parts are joined with dots, and empty parts are left out")
    func make() {
        #expect(AccessibilityIdentifier.make("copy", "Inbox URL") == "copy.inbox-url")
        #expect(AccessibilityIdentifier.make("card", "", "open") == "card.open")
    }

    @Test("Page actions keep the identifier that the caller gives")
    func pageAction() {
        #expect(PageAction("Stop", identifier: "site.stop") {}.identifier == "site.stop")
        #expect(PageAction("Stop") {}.identifier == nil)
    }

    @Test("Sheet buttons get identifiers from the sheet identifier")
    func sheetButtons() {
        let confirmation = SheetConfirmation("Save", identifier: "site-editor") {}
        #expect(confirmation.confirmIdentifier == "site-editor.confirm")
        #expect(confirmation.cancelIdentifier == "site-editor.cancel")
        #expect(SheetConfirmation("Save") {}.confirmIdentifier == nil)
    }

    @Test("Copy, Open, and Dismiss buttons get stable identifiers from their subject")
    func derivedIdentifiers() {
        #expect(CopyButton(subject: "Inbox URL") {}.identifier == "copy.inbox-url")
        let card = SummaryCard(
            "Sites", systemImage: "globe", tint: .sites, status: DisplayStatus("Ready", tone: .ready), summary: "",
            open: {})
        #expect(card.openIdentifier == "card.sites.open")
        let namedCard = SummaryCard(
            "Sites", systemImage: "globe", tint: .sites, status: DisplayStatus("Ready", tone: .ready), summary: "",
            identifier: "dashboard.sites", open: {})
        #expect(namedCard.openIdentifier == "dashboard.sites.open")
        #expect(InlineMessage("Failed.", kind: .error, dismiss: {}).dismissIdentifier == "message.error.dismiss")
        #expect(
            InlineMessage("Failed.", kind: .error, identifier: "site.error", dismiss: {}).dismissIdentifier
                == "site.error.dismiss")
    }

    @Test("Message details have a stable identifier, and empty details show no disclosure")
    func messageDetails() {
        let details = InlineMessageDetails(title: "Last log lines", lines: ["[ERROR] Aborting"])
        #expect(
            InlineMessage("Failed.", kind: .error, identifier: "mail.failed").detailsIdentifier == "mail.failed.details"
        )
        #expect(InlineMessage("Failed.", kind: .error).detailsIdentifier == "message.error.details")
        #expect(InlineMessage("Failed.", kind: .error, details: details).details == details)
        let empty = InlineMessageDetails(title: "Last log lines", lines: [])
        #expect(InlineMessage("Failed.", kind: .error, details: empty).details == nil)
    }
}
