import Foundation
import JerdUIFixtures
import JerdWeb
import Testing

@testable import JerdUI

@Suite("Site editor", .timeLimit(.minutes(1)))
@MainActor
struct SiteEditorModelTests {
    private let projects = "\(SampleData.user)/Projects"

    private func makeEditor(
        site: Site? = nil, port: InMemorySitesPort = InMemorySitesPort(),
        panels: InMemoryFilePanels = InMemoryFilePanels()
    ) -> SiteEditorModel {
        SiteEditorModel(site: site, configuration: SampleData.siteConfiguration, port: port, panels: panels)
    }

    @Test("A new folder sets the name and hostname that still follow the folder")
    func folderSuggestions() {
        let editor = makeEditor()
        editor.useProjectFolder("\(projects)/aurora")
        #expect(editor.displayName == "aurora")
        #expect(editor.hostname == "aurora.test")
        editor.useProjectFolder("\(projects)/borealis")
        #expect(editor.displayName == "borealis")
        #expect(editor.hostname == "borealis.test")
    }

    @Test("Typed names and hostnames stay when the folder changes")
    func typedValuesStay() {
        let editor = makeEditor()
        editor.useProjectFolder("\(projects)/aurora")
        editor.displayName = "Aurora Admin"
        editor.hostname = "admin.test"
        editor.useProjectFolder("\(projects)/borealis")
        #expect(editor.displayName == "Aurora Admin")
        #expect(editor.hostname == "admin.test")
    }

    @Test("A change of the folder or the document root, and each inspection, clears the confirmation")
    func confirmationResets() async {
        let editor = makeEditor()
        editor.useProjectFolder("\(projects)/aurora")
        editor.documentRoot = "\(projects)/aurora"
        editor.isRootConfirmed = true
        editor.documentRoot = "\(projects)/aurora/web"
        #expect(!editor.isRootConfirmed)
        editor.isRootConfirmed = true
        editor.projectPath = "\(projects)/borealis"
        #expect(!editor.isRootConfirmed)
        editor.isRootConfirmed = true
        await editor.inspect()
        #expect(!editor.isRootConfirmed)
    }

    @Test("Setting the same value keeps the confirmation")
    func sameValueKeepsConfirmation() {
        let editor = makeEditor(site: SampleData.studio)
        editor.isRootConfirmed = true
        editor.documentRoot = SampleData.studio.documentRoot
        #expect(editor.isRootConfirmed)
    }

    @Test("A Laravel project served from public needs no confirmation; a plain project does")
    func laravelNeedsNoConfirmation() async {
        let path = "\(projects)/shop"
        let port = InMemorySitesPort()
        await port.configure { $0.suggestions[path] = DocumentRootSuggestion(path: "\(path)/public", isLaravel: true) }
        let editor = makeEditor(port: port)
        editor.useProjectFolder(path)
        await editor.inspect()
        #expect(editor.documentRoot == "\(path)/public")
        #expect(!editor.requiresConfirmation)
        #expect(editor.canSave)
        #expect(editor.suggestionText == "Laravel files found. The suggested document root is public.")
        editor.documentRoot = path
        #expect(editor.requiresConfirmation)
        #expect(!editor.canSave)
    }

    @Test("Save needs every field, a valid hostname, and a confirmed root")
    func saveRules() {
        let editor = makeEditor()
        #expect(!editor.canSave)
        editor.useProjectFolder("\(projects)/aurora")
        editor.documentRoot = "\(projects)/aurora"
        #expect(!editor.canSave)
        editor.isRootConfirmed = true
        #expect(editor.canSave)
        editor.hostname = "aurora.local"
        #expect(editor.hostnameMessage != nil)
        #expect(!editor.canSave)
        editor.hostname = "  Aurora.TEST "
        #expect(editor.hostnameMessage == nil)
        #expect(editor.draft.hostname == "aurora.test")
    }

    @Test("Choose asks for a folder and inspects it; Cancel in the panel changes nothing")
    func chooseFolder() async {
        let panels = InMemoryFilePanels(answers: [URL(fileURLWithPath: "\(projects)/aurora"), nil])
        let port = InMemorySitesPort()
        let editor = makeEditor(port: port, panels: panels)
        await editor.chooseProjectFolder()
        #expect(editor.projectPath == "\(projects)/aurora")
        #expect(editor.suggestionText == "Plain PHP project. Select and confirm its document root.")
        #expect(panels.requests.map(\.kind) == [.folder])
        await editor.chooseDocumentRoot()
        #expect(editor.documentRoot == "\(projects)/aurora")
        #expect(await port.calls == ["inspect \(projects)/aurora"])
    }

    @Test("The PHP picker offers the default, each runtime, and a missing pin")
    func phpChoices() {
        let missing = UUID()
        var site = SampleData.studio
        site.phpSelection = .pinned(missing)
        let titles = makeEditor(site: site).phpChoices.map(\.title)
        #expect(titles.first == "Follow Default (PHP 8.4.12)")
        #expect(titles.count == SampleData.siteConfiguration.runtimes.count + 2)
        #expect(titles.last == "Pinned runtime unavailable")
        #expect(PHPChoice.summary(for: site, in: SampleData.siteConfiguration) == "Pinned: runtime unavailable")
        #expect(
            PHPChoice.summary(for: SampleData.studio, in: SampleData.siteConfiguration) == "Follow default: PHP 8.4.12")
    }

    @Test("Save of a new site hands over to the HTTPS approval, which starts it")
    func saveNewSite() async throws {
        let harness = await SitesHarness.launched()
        harness.model.beginAdd()
        let editor = try #require(harness.model.sheet?.editor)
        editor.useProjectFolder("\(projects)/aurora")
        editor.documentRoot = "\(projects)/aurora"
        editor.isRootConfirmed = true
        await harness.model.save(editor)?.value
        let approval = try #require(harness.model.sheet?.approval)
        #expect(approval.hostnames.contains("aurora.test"))
        await harness.model.approve(approval)?.value
        #expect(harness.model.sheet == nil)
        let id = try #require(harness.model.sites.last?.id)
        #expect(harness.model.environment.siteIDs == [id])
        #expect(await harness.sites.calls.contains("apply save aurora.test confirmed=true"))
    }

    @Test("A failed save shows in the editor, not on the page; Cancel closes without other effects")
    func saveFailure() async throws {
        let port = InMemorySitesPort()
        let harness = await SitesHarness.launched(sites: port)
        harness.model.beginEdit(SampleData.studio)
        let editor = try #require(harness.model.sheet?.editor)
        editor.isRootConfirmed = true
        await port.configure { $0.failure = "This hostname is already registered." }
        await harness.model.save(editor)?.value
        #expect(editor.failure == "This hostname is already registered.")
        #expect(harness.model.operation == .idle)
        await port.configure { $0.failure = nil }
        await harness.model.save(editor)?.value
        #expect(harness.model.sheet == nil)
        #expect(harness.recorder.shown == [.item(.site(SampleData.studioID))])
        harness.model.beginEdit(SampleData.studio)
        harness.model.cancelEditor()
        #expect(harness.model.sheet == nil)
        #expect(await !port.calls.contains("request stop"))
    }
}
