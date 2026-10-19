import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct SiteAliasesTests {
    @Test func theEditorTextSplitsOnCommasSpacesAndLineBreaks() {
        #expect(
            SiteAliases.parse(" API.app.test, admin.app.test\nb.app.test  ,") == [
                "api.app.test", "admin.app.test", "b.app.test",
            ])
        #expect(SiteAliases.parse("  ").isEmpty)
        #expect(SiteAliases.text(["a.app.test", "b.app.test"]) == "a.app.test, b.app.test")
    }

    @Test func validAliasesAreLowercaseAndSorted() throws {
        #expect(
            try SiteAliases.validate(["B.app.test", "a.app.test"], hostname: "app.test") == [
                "a.app.test", "b.app.test",
            ])
        #expect(try SiteAliases.validate([], hostname: "app.test").isEmpty)
    }

    @Test func eachBrokenRuleHasItsOwnMessage() {
        #expect(
            throws: JerdError.invalid(
                "The alias app.example is not valid. Use a hostname ending in .test, without spaces or a port.")
        ) { try SiteAliases.validate(["app.example"], hostname: "app.test") }
        #expect(throws: JerdError.invalid("Remove the alias that is the same as the hostname.")) {
            try SiteAliases.validate(["APP.test"], hostname: "app.test")
        }
        #expect(throws: JerdError.invalid("Enter the alias a.app.test only once.")) {
            try SiteAliases.validate(["a.app.test", "A.app.test"], hostname: "app.test")
        }
    }
}
