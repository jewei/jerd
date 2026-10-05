import Foundation
import JerdFoundation
import Testing

@testable import JerdWeb

@Suite struct SiteValidatorTests {
    let validator = SiteValidator()

    @Test func validationNormalizesNameHostnameAndPathsAndKeepsTheRest() throws {
        let folder = try TemporaryDirectory(" café 项目")
        defer { folder.remove() }
        let link = folder.path("alias")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: folder.url)
        var draft = Samples.site(link, hostname: "SHOP.Example.test", selection: .pinned(Samples.runtimeID))
        draft.displayName = "  Shop \n"
        draft.isEnabled = false
        let site = try validator.validate(draft, existing: [], documentRootConfirmed: true)
        #expect(site.displayName == "Shop")
        #expect(site.hostname == "shop.example.test")
        #expect(site.projectPath == folder.url.path)
        #expect(site.documentRoot == folder.url.path)
        #expect(site.id == draft.id && site.phpSelection == draft.phpSelection && !site.isEnabled)
    }

    @Test func theFirstBrokenRuleDecidesTheMessage() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let outside = try TemporaryDirectory()
        defer { outside.remove() }
        var draft = Samples.site(folder.url, hostname: "bad host")
        draft.displayName = " "
        draft.documentRoot = outside.url.path
        let steps: [(JerdError, (inout Site) -> Void)] = [
            (.invalid("Enter a site name."), { $0.displayName = "Demo" }),
            (.invalid("Use a hostname ending in .test, without spaces or a port."), { $0.hostname = "demo.test" }),
            (.invalid("The document root must be inside the project directory."), { $0.documentRoot = $0.projectPath }),
        ]
        for (error, fix) in steps {
            #expect(throws: error) { try validator.validate(draft, existing: [], documentRootConfirmed: true) }
            fix(&draft)
        }
        #expect(throws: JerdError.invalid("Confirm the document root before saving this site.")) {
            try validator.validate(draft, existing: [], documentRootConfirmed: false)
        }
        let other = Samples.site(folder.url, hostname: "DEMO.test")
        #expect(throws: JerdError.invalid("This hostname is already registered.")) {
            try validator.validate(draft, existing: [other], documentRootConfirmed: true)
        }
        #expect(throws: JerdError.invalid("This project directory is already registered.")) {
            try validator.validate(
                draft, existing: [Samples.site(folder.url, hostname: "x.test")], documentRootConfirmed: true)
        }
        #expect(throws: JerdError.invalid("This hostname has a conflicting /etc/hosts entry. Choose another hostname."))
        {
            try validator.validate(draft, existing: [], hostsText: "10.0.0.1 demo.test", documentRootConfirmed: true)
        }
    }

    @Test func missingRootsParentRootsAndEscapingLinksAreRejected() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let outside = try TemporaryDirectory()
        defer { outside.remove() }
        var draft = Samples.site(folder.url)
        for root in [folder.path("missing").path, folder.url.deletingLastPathComponent().path] {
            draft.documentRoot = root
            #expect(throws: JerdError.self) { try validator.validate(draft, existing: [], documentRootConfirmed: true) }
        }
        let escape = folder.path("escape")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside.url)
        draft.documentRoot = escape.path
        #expect(throws: JerdError.invalid("The document root must be inside the project directory.")) {
            try validator.validate(draft, existing: [], documentRootConfirmed: true)
        }
    }

    @Test func aLaravelPublicRootNeedsNoConfirmationButAnotherRootDoes() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        for marker in ProjectDetector.laravelMarkers { try folder.file(marker) }
        var draft = Samples.site(folder.url, documentRoot: folder.path("public"))
        #expect(
            try validator.validate(draft, existing: [], documentRootConfirmed: false).documentRoot
                == folder.path("public").path)
        draft.documentRoot = folder.url.path
        #expect(throws: JerdError.self) { try validator.validate(draft, existing: [], documentRootConfirmed: false) }
    }

    @Test func editingKeepsTheOwnRecordAndLinkAliasesAreDuplicates() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let first = try validator.validate(Samples.site(folder.url), existing: [], documentRootConfirmed: true)
        var edited = first
        edited.displayName = "New name"
        #expect(
            try validator.validate(edited, existing: [first], documentRootConfirmed: true).displayName == "New name")
        let alias = folder.path("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder.url)
        #expect(throws: JerdError.invalid("This project directory is already registered.")) {
            try validator.validate(
                Samples.site(alias, hostname: "alias.test"), existing: [first], documentRootConfirmed: true)
        }
        let nested = try folder.folder("nested")
        #expect(throws: Never.self) {
            try validator.validate(
                Samples.site(nested, hostname: "nested.test"), existing: [first], documentRootConfirmed: true)
        }
    }

    @Test func revalidationRejectsDuplicatesInsideOnePlan() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let one = Samples.site(folder.url, hostname: "one.test")
        #expect(try validator.revalidate([one]).count == 1)
        #expect(throws: JerdError.self) {
            try validator.revalidate([one, Samples.site(folder.url, hostname: "two.test")])
        }
    }
}
