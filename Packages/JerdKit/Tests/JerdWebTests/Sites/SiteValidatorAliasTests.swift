import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@testable import JerdWeb

@Suite struct SiteValidatorAliasTests {
    let validator = SiteValidator()

    @Test func aliasesAreNormalizedWithTheSite() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var draft = Samples.site(folder.url, hostname: "app.test")
        draft.aliases = ["B.app.test", "a.app.test"]
        let site = try validator.validate(draft, existing: [], documentRootConfirmed: true)
        #expect(site.aliases == ["a.app.test", "b.app.test"])
        #expect(site.servedHostnames == ["app.test", "a.app.test", "b.app.test"])
    }

    @Test func anAliasMustNotBeAnotherSitesHostnameOrAlias() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let other = try TemporaryDirectory()
        defer { other.remove() }
        var registered = Samples.site(other.url, hostname: "shop.test")
        registered.aliases = ["admin.shop.test"]
        for taken in ["shop.test", "ADMIN.shop.test"] {
            var draft = Samples.site(folder.url, hostname: "app.test")
            draft.aliases = [taken]
            #expect(throws: JerdError.invalid("The alias \(taken.lowercased()) is already registered.")) {
                try validator.validate(draft, existing: [registered], documentRootConfirmed: true)
            }
        }
        let draft = Samples.site(folder.url, hostname: "admin.shop.test")
        #expect(throws: JerdError.invalid("This hostname is already registered.")) {
            try validator.validate(draft, existing: [registered], documentRootConfirmed: true)
        }
    }

    @Test func anAliasWithAConflictingHostsEntryIsRefused() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var draft = Samples.site(folder.url, hostname: "app.test")
        draft.aliases = ["api.app.test"]
        #expect(
            throws: JerdError.invalid(
                "The alias api.app.test has a conflicting /etc/hosts entry. Choose another alias.")
        ) {
            try validator.validate(
                draft, existing: [], hostsText: "10.0.0.1 api.app.test", documentRootConfirmed: true)
        }
    }
}
