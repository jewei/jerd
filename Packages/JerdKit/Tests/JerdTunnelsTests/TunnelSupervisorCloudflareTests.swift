import Foundation
import JerdFoundation
import JerdTestSupport
import Testing

@testable import JerdTunnels

@Suite("Tunnel supervisor and Cloudflare")
struct TunnelSupervisorCloudflareTests {
    private let folder: TemporaryDirectory
    private let secrets = FakeSecretStore()
    private let cloudflare = FakeCloudflare()
    private let supervisor: TunnelSupervisor
    private let registration = TunnelRegistration(
        name: "A", hostname: "a.example.com", originURL: "http://127.0.0.1:8000", routing: .local)

    init() async throws {
        folder = try TemporaryDirectory(" tunnels")
        supervisor = TunnelSupervisor(
            layout: folder.layout, secrets: secrets, connector: FakeConnector(), cloudflare: cloudflare,
            clock: ManualClock())
        try await supervisor.load()
    }

    @Test("Create saves the registration with its record and token, and does not connect")
    func createSaves() async throws {
        defer { folder.remove() }
        try await supervisor.create(registration, in: FakeCloudflareTransport.exampleZone)
        let saved = try #require(await supervisor.currentConfiguration().registration(registration.id))
        #expect(saved.cloudflare == FakeCloudflare.record)
        #expect(await secrets.values[registration.id] == TokenSamples.valid)
        #expect(await cloudflare.calls == ["provision a.example.com jerd-a.example.com"])
        #expect(await supervisor.snapshots().first?.state == .stopped)
        let settings = try String(contentsOf: folder.layout.settingsFile, encoding: .utf8)
        #expect(!settings.contains(TokenSamples.secret))
    }

    @Test("Create refuses a hostname outside the zone before any Cloudflare call")
    func hostnameOutsideZone() async throws {
        defer { folder.remove() }
        var other = registration
        other.hostname = "a.example.org"
        await #expect(throws: JerdError.self) {
            try await supervisor.create(other, in: FakeCloudflareTransport.exampleZone)
        }
        #expect(await cloudflare.calls.isEmpty)
    }

    @Test("Create refuses a hostname two levels below the zone, which the free certificate does not cover")
    func deepHostnameIsRefused() async throws {
        defer { folder.remove() }
        var deep = registration
        deep.hostname = "app.dev.example.com"
        await #expect(throws: JerdError.invalid(CloudflareMessage.subdomainLevel)) {
            try await supervisor.create(deep, in: FakeCloudflareTransport.exampleZone)
        }
        #expect(await cloudflare.calls.isEmpty)
    }

    @Test("The free certificate covers the domain and one level below it")
    func certificateCoverage() {
        let zone = FakeCloudflareTransport.exampleZone
        #expect(zone.isCertificateCovered("example.com"))
        #expect(zone.isCertificateCovered("dev.example.com"))
        #expect(!zone.isCertificateCovered("app.dev.example.com"))
        #expect(!zone.isCertificateCovered("example.org"))
        #expect(!zone.isCertificateCovered("badexample.com"))
    }

    @Test("A failed save deletes the new token and the Cloudflare resources")
    func failedSaveUndoes() async throws {
        defer { folder.remove() }
        try AtomicFile.write(Data("not-json".utf8), to: folder.layout.settingsFile)
        await #expect(throws: (any Error).self) {
            try await supervisor.create(registration, in: FakeCloudflareTransport.exampleZone)
        }
        #expect(await secrets.values[registration.id] == nil)
        #expect(await cloudflare.calls.last?.hasPrefix("deprovision") == true)
        #expect(await supervisor.currentConfiguration().tunnels.isEmpty)
    }

    @Test("Remove from Cloudflare deletes the resources, then the registration")
    func removeFromCloudflare() async throws {
        defer { folder.remove() }
        try await supervisor.create(registration, in: FakeCloudflareTransport.exampleZone)
        try await supervisor.removeFromCloudflare(id: registration.id)
        #expect(await cloudflare.calls.last?.hasPrefix("deprovision") == true)
        #expect(await supervisor.currentConfiguration().tunnels.isEmpty)
        #expect(await secrets.values[registration.id] == nil)
    }

    @Test("When Cloudflare refuses the delete, the registration and token stay")
    func refusedDeleteKeepsRegistration() async throws {
        defer { folder.remove() }
        try await supervisor.create(registration, in: FakeCloudflareTransport.exampleZone)
        await cloudflare.setDeprovisionFailure(.unavailable("Cloudflare refused the request: busy"))
        await #expect(throws: JerdError.unavailable("Cloudflare refused the request: busy")) {
            try await supervisor.removeFromCloudflare(id: registration.id)
        }
        #expect(await supervisor.currentConfiguration().registration(registration.id) != nil)
        #expect(await secrets.values[registration.id] == TokenSamples.valid)
    }

    @Test("A tunnel that the user brought cannot be deleted in Cloudflare")
    func existingTunnelIsNeverDeleted() async throws {
        defer { folder.remove() }
        try await supervisor.save(registration, token: TokenSamples.valid)
        await #expect(throws: JerdError.invalid(CloudflareMessage.notCreatedByJerd)) {
            try await supervisor.removeFromCloudflare(id: registration.id)
        }
        #expect(await cloudflare.calls.isEmpty)
    }
}

extension TunnelSupervisorCloudflareTests {
    @Test("Save keeps the Cloudflare record and refuses a new hostname for a created tunnel")
    func saveKeepsCreatedTunnel() async throws {
        defer { folder.remove() }
        try await supervisor.create(registration, in: FakeCloudflareTransport.exampleZone)
        var edited = registration
        edited.name = "Renamed"
        try await supervisor.save(edited, token: nil)
        #expect(
            await supervisor.currentConfiguration().registration(registration.id)?.cloudflare == FakeCloudflare.record)
        edited.routing = .cloudflare
        await #expect(throws: JerdError.invalid(CloudflareMessage.routingFixed)) {
            try await supervisor.save(edited, token: nil)
        }
        edited.routing = .local
        edited.hostname = "b.example.com"
        await #expect(throws: JerdError.invalid(CloudflareMessage.hostnameFixed)) {
            try await supervisor.save(edited, token: nil)
        }
    }

    @Test("Save accepts only a token of the created tunnel")
    func saveRefusesOtherTunnelToken() async throws {
        defer { folder.remove() }
        try await supervisor.create(registration, in: FakeCloudflareTransport.exampleZone)
        await #expect(throws: JerdError.invalid(CloudflareMessage.otherTunnelToken)) {
            try await supervisor.save(registration, token: TokenSamples.other)
        }
        try await supervisor.save(registration, token: TokenSamples.rotated)
    }

    @Test("Save never adds a Cloudflare record")
    func saveNeverAddsRecord() async throws {
        defer { folder.remove() }
        var forged = registration
        forged.cloudflare = FakeCloudflare.record
        try await supervisor.save(forged, token: TokenSamples.valid)
        #expect(await supervisor.currentConfiguration().registration(registration.id)?.cloudflare == nil)
    }
}
