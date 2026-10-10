import Foundation
import JerdTunnels
import JerdUIFixtures
import JerdWeb
import Testing

@testable import JerdUI

/// The rules of the Sites sheets: a disabled Save names its reason, and a late inspection
/// never sets the document root of another folder.
@Suite("Sites sheet rules", .timeLimit(.minutes(1)))
@MainActor
struct SheetRulesTests {
    private let projects = "\(SampleData.user)/Projects"

    @Test("An inspection result for a folder that changed meanwhile is dropped")
    func staleInspectionIsDropped() async {
        let port = InMemorySitesPort()
        let gate = FixtureGate()
        let first = "\(projects)/aurora"
        await port.configure { port in
            port.inspectionGates[first] = gate
            port.suggestions[first] = DocumentRootSuggestion(path: "\(first)/public", isLaravel: true)
        }
        let editor = SiteEditorModel(
            site: nil, configuration: SampleData.siteConfiguration, port: port, panels: InMemoryFilePanels())
        editor.useProjectFolder(first)
        let inspection = Task { await editor.inspect() }
        var turns = 0
        while await !gate.isHolding, turns < 1_000 {
            turns += 1
            await Task.yield()
        }
        editor.useProjectFolder("\(projects)/borealis")
        await gate.open()
        await inspection.value
        #expect(editor.suggestion == nil)
        #expect(editor.documentRoot.isEmpty)
        #expect(editor.requiresConfirmation)
    }

    @Test("A disabled site Save names its reason: empty fields first, then the root confirmation")
    func siteSaveRequirement() {
        let editor = SiteEditorModel(
            site: nil, configuration: SampleData.siteConfiguration, port: InMemorySitesPort(),
            panels: InMemoryFilePanels())
        #expect(
            editor.saveRequirement
                == "To save, enter a project folder, a display name, a hostname, and a document root.")
        editor.useProjectFolder("\(projects)/aurora")
        editor.documentRoot = "\(projects)/aurora"
        #expect(editor.saveRequirement == "To save, confirm the document root under Document Root.")
        editor.isRootConfirmed = true
        #expect(editor.canSave)
        #expect(editor.saveRequirement == nil)
        editor.hostname = "bad host"
        #expect(editor.hostnameMessage != nil)
        #expect(editor.saveRequirement == nil)
    }

    @Test("A disabled tunnel Save names its reason, also the route confirmation at the end of the form")
    func tunnelSaveRequirement() {
        let editor = TunnelEditorModel(tunnel: nil, sites: [SampleData.studio], suggestedPort: 20_243)
        #expect(
            editor.saveRequirement
                == "To save, enter a name, a public hostname, a tunnel token, and a local address.")
        editor.name = "Preview"
        editor.hostname = "preview.example.com"
        editor.token = "token"
        editor.originURL = TunnelEditorModel.defaultOrigin
        #expect(
            editor.saveRequirement
                == "To save, select “I checked that this tunnel is locally managed.” at the end of this form.")
        editor.routeChecked = true
        #expect(editor.canSave)
        #expect(editor.saveRequirement == nil)
        editor.siteID = UUID()
        #expect(editor.saveRequirement == "The linked site was removed. To save, choose a destination.")
        editor.siteID = nil
        editor.hostname = "localhost"
        #expect(editor.validationMessage != nil)
        #expect(editor.saveRequirement == nil)
    }

    @Test("An earlier registration keeps Cloudflare routing until the user chooses Jerd and confirms it")
    func earlierTunnelCanSelectLocalRouting() {
        let tunnel = TunnelRegistration(name: "Preview", hostname: "preview.example.com", siteID: SampleData.studio.id)
        let editor = TunnelEditorModel(tunnel: tunnel, sites: [SampleData.studio])
        #expect(editor.routing == .cloudflare)
        editor.routeChecked = true
        #expect(editor.canSave)
        editor.routing = .local
        #expect(!editor.canSave)
        editor.routeChecked = true
        #expect(editor.canSave)
        #expect(editor.registration?.routing == .local)
        #expect(editor.registration?.siteID == tunnel.siteID)
        #expect(editor.tokenToSave == nil)
    }

    @Test("A requirement list reads as English")
    func listedRequirement() {
        #expect(SaveRequirement.listed(["a name"]) == "a name")
        #expect(SaveRequirement.listed(["a name", "a hostname"]) == "a name and a hostname")
        #expect(SaveRequirement.listed(["a", "b", "c"]) == "a, b, and c")
    }
}
