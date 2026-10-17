import Foundation
import JerdTunnels
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Tunnel create in Cloudflare", .timeLimit(.minutes(1)))
@MainActor
struct TunnelCreateTests {
    private func openEditor(connected: Bool) async throws -> (SitesHarness, TunnelEditorModel) {
        let port = InMemoryTunnelsPort(configuration: TunnelConfiguration(), states: [:])
        await port.configure { $0.cloudflareConnected = connected }
        let harness = await SitesHarness.launched(tunnels: port)
        await harness.model.tunnels.beginAdd(sites: harness.model.sites)?.value
        return (harness, try #require(harness.model.tunnels.sheet?.editor))
    }

    @Test("A new tunnel starts in Create mode and asks to connect Cloudflare first")
    func notConnectedAsksToConnect() async throws {
        let (_, editor) = try await openEditor(connected: false)
        #expect(editor.isCreating)
        #expect(editor.isCloudflareConnected == false)
        #expect(!editor.canSave)
        #expect(editor.saveRequirement == "To create a tunnel, connect Cloudflare with an API token.")
    }

    @Test("Connect saves the API token, clears the field, and selects the first domain")
    func connectShowsZones() async throws {
        let (harness, editor) = try await openEditor(connected: false)
        editor.apiToken = " api-token "
        await harness.model.tunnels.connectCloudflare(editor)?.value
        #expect(editor.isCloudflareConnected == true)
        #expect(editor.zones == SampleData.cloudflareZones)
        #expect(editor.zoneID == SampleData.cloudflareZones.first?.id)
        #expect(editor.apiToken.isEmpty)
        #expect(await harness.tunnels.calls.contains("connect cloudflare"))
    }

    @Test("A failed Connect shows in the editor")
    func failedConnectShowsInEditor() async throws {
        let (harness, editor) = try await openEditor(connected: false)
        await harness.tunnels.configure { $0.cloudflareFailure = "Cloudflare rejected the API token." }
        editor.apiToken = "api-token"
        await harness.model.tunnels.connectCloudflare(editor)?.value
        #expect(editor.failure == "Cloudflare rejected the API token.")
        #expect(harness.model.tunnels.operation == .idle)
    }

    @Test("Create needs only a domain, a subdomain, and a destination, then connects")
    func createConnects() async throws {
        let (harness, editor) = try await openEditor(connected: true)
        let model = harness.model.tunnels
        editor.subdomain = "Dev"
        editor.siteID = SampleData.studioID
        #expect(editor.publicHostname == "dev.example.com")
        #expect(editor.canSave)
        await model.save(editor)?.value
        #expect(model.sheet == nil)
        let created = try #require(model.registrations.first)
        #expect(created.name == "dev.example.com")
        #expect(created.routing == .local)
        #expect(created.cloudflare == SampleData.cloudflareRecord)
        #expect(model.state(of: created.id) == .connected)
        let calls = await harness.tunnels.calls
        #expect(calls.contains("create dev.example.com in example.com"))
        #expect(calls.contains("connect \(created.id.uuidString.prefix(8))"))
        #expect(harness.recorder.shown.last == .item(.tunnel(created.id)))
    }

    @Test("A subdomain with a dot is refused, because the free certificate covers one level only")
    func deepSubdomainIsRefused() async throws {
        let (_, editor) = try await openEditor(connected: true)
        editor.subdomain = "app.dev"
        editor.siteID = SampleData.studioID
        #expect(editor.validationMessage == CloudflareMessage.subdomainLevel)
        #expect(!editor.canSave)
        editor.subdomain = "app"
        #expect(editor.validationMessage == nil)
        #expect(editor.canSave)
    }

    @Test("A Create that ends after Cancel keeps the tunnel stopped and says so")
    func cancelledCreateDoesNotConnect() async throws {
        let (harness, editor) = try await openEditor(connected: true)
        let model = harness.model.tunnels
        let gate = FixtureGate()
        await harness.tunnels.configure { $0.saveGate = gate }
        editor.subdomain = "dev"
        editor.originURL = TunnelEditorModel.defaultOrigin
        let save = model.save(editor)
        model.cancelEditor()
        await gate.open()
        await save?.value
        let created = try #require(model.registrations.first)
        #expect(model.state(of: created.id) == .stopped)
        #expect(model.operation.failureMessage?.contains("before Cancel took effect") == true)
        #expect(harness.recorder.shown.isEmpty)
    }

    @Test("A failed Create stays in the editor and connects nothing")
    func failedCreateStaysInEditor() async throws {
        let (harness, editor) = try await openEditor(connected: true)
        await harness.tunnels.configure { $0.cloudflareFailure = "dev.example.com already has a DNS record." }
        editor.subdomain = "dev"
        editor.originURL = TunnelEditorModel.defaultOrigin
        await harness.model.tunnels.save(editor)?.value
        #expect(editor.failure == "dev.example.com already has a DNS record.")
        #expect(harness.model.tunnels.registrations.isEmpty)
        #expect(
            await harness.tunnels.calls.allSatisfy {
                !$0.hasPrefix("connect ") || $0 == "connect startup" || $0 == "connect cloudflare"
            })
    }

    @Test("Disconnect forgets the account in the editor")
    func disconnect() async throws {
        let (harness, editor) = try await openEditor(connected: true)
        await harness.model.tunnels.disconnectCloudflare(editor)?.value
        #expect(editor.isCloudflareConnected == false)
        #expect(editor.zones.isEmpty)
        #expect(await !harness.tunnels.cloudflareConnected)
    }

    @Test("A failed Keychain read shows the error and the Connect field")
    func failedKeychainReadShowsConnect() async throws {
        let port = InMemoryTunnelsPort(configuration: TunnelConfiguration(), states: [:])
        await port.configure { $0.cloudflareReadFailure = "Jerd cannot read the Keychain." }
        let harness = await SitesHarness.launched(tunnels: port)
        await harness.model.tunnels.beginAdd(sites: harness.model.sites)?.value
        let editor = try #require(harness.model.tunnels.sheet?.editor)
        #expect(editor.isCloudflareConnected == false)
        #expect(editor.failure == "Jerd cannot read the Keychain.")
    }

    @Test("A failed domain load shows in the editor, and Load Domains loads them again")
    func failedZoneLoadCanBeRetried() async throws {
        let port = InMemoryTunnelsPort(configuration: TunnelConfiguration(), states: [:])
        await port.configure {
            $0.cloudflareConnected = true
            $0.zonesFailure = "Jerd cannot reach the Cloudflare API."
        }
        let harness = await SitesHarness.launched(tunnels: port)
        let model = harness.model.tunnels
        await model.beginAdd(sites: harness.model.sites)?.value
        let editor = try #require(model.sheet?.editor)
        #expect(editor.failure == "Jerd cannot reach the Cloudflare API.")
        #expect(editor.zones.isEmpty)
        #expect(model.operation == .idle)
        await port.configure { $0.zonesFailure = nil }
        await model.loadCloudflareZones(editor)?.value
        #expect(editor.failure == nil)
        #expect(editor.zones == SampleData.cloudflareZones)
    }

    @Test("Disconnect is off while the domains load, so a late answer cannot connect the account again")
    func disconnectWaitsForZoneLoad() async throws {
        let port = InMemoryTunnelsPort(configuration: TunnelConfiguration(), states: [:])
        let gate = FixtureGate()
        await port.configure {
            $0.cloudflareConnected = true
            $0.zonesGate = gate
        }
        let harness = await SitesHarness.launched(tunnels: port)
        let model = harness.model.tunnels
        let open = model.beginAdd(sites: harness.model.sites)
        while await !gate.isHolding { await Task.yield() }
        let editor = try #require(model.sheet?.editor)
        #expect(!model.canChange)
        #expect(model.disconnectCloudflare(editor) == nil)
        await gate.open()
        await open?.value
        #expect(model.canChange)
        #expect(editor.zones == SampleData.cloudflareZones)
    }

    @Test("Remove offers to delete in Cloudflare only for a tunnel that Jerd created")
    func removeChoices() async throws {
        var created = SampleData.docsTunnel
        created.cloudflare = SampleData.cloudflareRecord
        #expect(TunnelConfirmation.remove(created).cloudflareDeleteTitle == "Remove and Delete in Cloudflare")
        #expect(TunnelConfirmation.remove(SampleData.docsTunnel).cloudflareDeleteTitle == nil)
        let port = InMemoryTunnelsPort(configuration: TunnelConfiguration(tunnels: [created]), states: [:])
        let harness = await SitesHarness.launched(tunnels: port)
        harness.model.tunnels.confirmation = .remove(created)
        await harness.model.tunnels.confirm(deleteInCloudflare: true)?.value
        #expect(await port.calls.contains("remove from cloudflare \(created.id.uuidString.prefix(8))"))
        #expect(harness.model.tunnels.registrations.isEmpty)
    }

    @Test("Plain Remove of a created tunnel keeps it in Cloudflare")
    func plainRemoveKeepsCloudflare() async throws {
        var created = SampleData.docsTunnel
        created.cloudflare = SampleData.cloudflareRecord
        let port = InMemoryTunnelsPort(configuration: TunnelConfiguration(tunnels: [created]), states: [:])
        let harness = await SitesHarness.launched(tunnels: port)
        harness.model.tunnels.confirmation = .remove(created)
        await harness.model.tunnels.confirm()?.value
        #expect(await port.calls.contains("remove \(created.id.uuidString.prefix(8))"))
        #expect(await !port.calls.contains { $0.hasPrefix("remove from cloudflare") })
    }
}
