import Foundation
import JerdFoundation
import JerdTunnels
import Testing

@Suite struct TunnelSupervisorSettingsTests {
    @Test func saveNeverConnectsAndKeepsTheTokenOutOfSettings() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        let settings = text(fixture.folder.layout.settingsFile)
        #expect(settings.contains("preview.example.com"))
        #expect(!settings.contains(TokenSamples.valid))
        #expect(!settings.contains(TokenSamples.secret))
        #expect(await fixture.secrets.values[fixture.id] == TokenSamples.valid)
        #expect(await fixture.connector.launches.isEmpty)
        #expect(await fixture.state() == .stopped)
    }

    @Test func loadNeverConnectsAStartupTunnel() async throws {
        let first = try await SupervisorFixture(startOnLaunch: true)
        defer { first.folder.remove() }
        let connector = FakeConnector()
        let reopened = TunnelSupervisor(
            layout: first.folder.layout, secrets: first.secrets, connector: connector, clock: ManualClock())
        let loaded = try await reopened.load()
        #expect(loaded.tunnels.first?.startOnLaunch == true)
        #expect(await connector.launches.isEmpty)
        #expect(await reopened.snapshots().first?.state == .stopped)
    }

    @Test func unreadableSettingsArePreservedAndBlockChanges() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        try OwnedDirectory.create(folder.layout.root)
        try AtomicFile.write(Data("not-json".utf8), to: folder.layout.settingsFile)
        let supervisor = TunnelSupervisor(layout: folder.layout, secrets: FakeSecretStore(), connector: FakeConnector())
        let error = try await #require(throws: JerdError.self) { try await supervisor.load() }
        #expect(error.kind == .corrupt)
        await #expect(throws: JerdError.unavailable(TunnelMessage.notLoaded)) {
            try await supervisor.save(
                TunnelRegistration(name: "A", hostname: "a.example.com"), token: TokenSamples.valid)
        }
        #expect(text(folder.layout.settingsFile) == "not-json")
    }

    @Test func aSettingsSaveFailureRestoresTheEarlierToken() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        try AtomicFile.write(Data("not-json".utf8), to: fixture.folder.layout.settingsFile)
        await #expect(throws: JerdError.self) {
            try await fixture.supervisor.save(fixture.registration, token: TokenSamples.rotated)
        }
        #expect(await fixture.secrets.values[fixture.id] == TokenSamples.valid)
        #expect(text(fixture.folder.layout.settingsFile) == "not-json")
        let second = TunnelRegistration(name: "Second", hostname: "two.example.com", metricsPort: 20_242)
        await #expect(throws: JerdError.self) { try await fixture.supervisor.save(second, token: TokenSamples.other) }
        #expect(await fixture.secrets.values[second.id] == nil)
    }

    @Test func aTokenThatCannotBePutBackIsReportedAsAPartialChange() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        try AtomicFile.write(Data("not-json".utf8), to: fixture.folder.layout.settingsFile)
        try await fixture.supervisor.remove(id: UUID())
        await fixture.secrets.setRefusesWrites(true)
        let error = try await #require(throws: JerdError.self) { try await fixture.supervisor.remove(id: fixture.id) }
        #expect(error.kind == .partialChange)
        #expect(error.message.hasSuffix("The earlier tunnel token could not be restored: Keychain is locked."))
    }

    @Test func rotatedDuplicateAndMalformedTokensAreRejected() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        let second = TunnelRegistration(name: "Duplicate", hostname: "two.example.com", metricsPort: 20_242)
        let cases: [(String, String)] = [
            (TokenSamples.rotated, TunnelMessage.duplicateTunnel), ("not-a-token", TunnelMessage.tokenFormat),
            ("cloudflared tunnel run --token secret", TunnelMessage.tokenCharacters),
            ("", TunnelMessage.tokenCharacters),
        ]
        for (token, message) in cases {
            await #expect(throws: JerdError.invalid(message)) {
                try await fixture.supervisor.save(second, token: token)
            }
        }
        await #expect(throws: JerdError.invalid(TunnelMessage.tokenRequired)) {
            try await fixture.supervisor.save(second)
        }
        #expect(await fixture.secrets.values[second.id] == nil)
        #expect(await fixture.supervisor.currentConfiguration().tunnels.count == 1)
        try await fixture.supervisor.save(fixture.registration, token: TokenSamples.rotated)
        #expect(await fixture.secrets.values[fixture.id] == TokenSamples.rotated)
    }

    @Test func editsKeepTheSavedTokenAndInvalidRegistrationsAreRefused() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        var renamed = fixture.registration
        renamed.name = "Renamed"
        try await fixture.supervisor.save(renamed)
        #expect(await fixture.supervisor.currentConfiguration().tunnels == [renamed])
        #expect(await fixture.secrets.values[fixture.id] == TokenSamples.valid)
        var invalid = renamed
        invalid.hostname = "10.0.0.1"
        await #expect(throws: JerdError.invalid(TunnelMessage.addressHostname)) {
            try await fixture.supervisor.save(invalid)
        }
        let samePort = TunnelRegistration(name: "Port", hostname: "port.example.com")
        await #expect(throws: JerdError.invalid(TunnelMessage.invalidConfiguration)) {
            try await fixture.supervisor.save(samePort, token: TokenSamples.other)
        }
    }

    @Test func removeDeletesTheTokenAndKeepsTheInstanceFolder() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        let instance = fixture.folder.layout.instance(fixture.id)
        try OwnedDirectory.create(instance.root)
        try await fixture.supervisor.remove(id: fixture.id)
        #expect(await fixture.secrets.values[fixture.id] == nil)
        #expect(await fixture.supervisor.currentConfiguration().tunnels.isEmpty)
        #expect(FileProbe.presence(at: instance.root) == .present)
        try await fixture.supervisor.remove(id: fixture.id)
    }

    /// Fix of spec E 7.1.19: the runtime ID no longer depends on how the runtime was chosen.
    @Test func aRuntimeIsSavedWithItsVersionIDAndIsLockedWhileConnected() async throws {
        let fixture = try await SupervisorFixture()
        defer { fixture.folder.remove() }
        #expect(await fixture.supervisor.currentConfiguration().runtime?.id == "cloudflared-2026.9.3")
        try await fixture.supervisor.start(id: fixture.id)
        await #expect(throws: JerdError.unavailable(TunnelMessage.runtimeInUse)) {
            try await fixture.supervisor.useRuntime(at: URL(fileURLWithPath: "/other/cloudflared"))
        }
        await #expect(throws: JerdError.unavailable(TunnelMessage.stopBeforeEdit)) {
            try await fixture.supervisor.save(fixture.registration)
        }
        await #expect(throws: JerdError.unavailable(TunnelMessage.stopBeforeRemove)) {
            try await fixture.supervisor.remove(id: fixture.id)
        }
        try await fixture.supervisor.stopAll()
    }

    @Test func connectGuardsExplainWhatIsMissing() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let supervisor = TunnelSupervisor(layout: folder.layout, secrets: FakeSecretStore(), connector: FakeConnector())
        await #expect(throws: JerdError.unavailable(TunnelMessage.notLoaded)) { try await supervisor.start(id: UUID()) }
        try await supervisor.load()
        await #expect(throws: JerdError.invalid(TunnelMessage.notRegistered)) { try await supervisor.start(id: UUID()) }
        let registration = TunnelRegistration(name: "A", hostname: "a.example.com")
        try await supervisor.save(registration, token: TokenSamples.valid)
        await #expect(throws: JerdError.unavailable(TunnelMessage.runtimeMissing)) {
            try await supervisor.start(id: registration.id)
        }
        await #expect(throws: JerdError.invalid(TunnelMessage.notRegistered)) { try await supervisor.log(id: UUID()) }
        #expect(try await supervisor.log(id: registration.id) == TunnelMessage.noLog)
        #expect(try await supervisor.suggestedPort() == 20_242)
    }
}
