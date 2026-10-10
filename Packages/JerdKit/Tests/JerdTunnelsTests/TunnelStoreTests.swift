import Foundation
import JerdFoundation
import JerdTestSupport
import JerdTunnels
import Testing

@Suite struct TunnelStoreTests {
    /// The exact bytes that earlier builds wrote: pretty, sorted keys, unescaped slashes, uppercase UUIDs,
    /// and no key for a nil `siteID`.
    static let golden = """
        {
          "runtime" : {
            "id" : "cloudflared-2026.9.3",
            "path" : "/Users/me/Library/Application Support/Jerd/runtimes/cloudflared",
            "version" : "2026.9.3"
          },
          "schemaVersion" : 1,
          "tunnels" : [
            {
              "hostname" : "preview.example.com",
              "id" : "32394787-9B89-41AE-A065-57520475754A",
              "metricsPort" : 20241,
              "name" : "Preview",
              "originURL" : "http://127.0.0.1:8000",
              "restartOnFailure" : true,
              "startOnLaunch" : false
            }
          ]
        }
        """

    @Test func earlierSettingsLoadAndSaveToTheSameBytes() throws {
        let folder = try TemporaryDirectory(" tunnels")
        defer { folder.remove() }
        let layout = folder.layout
        try OwnedDirectory.create(layout.root)
        try AtomicFile.write(Data(Self.golden.utf8), to: layout.settingsFile)
        let store = TunnelStore(layout: layout)
        let loaded = try store.load()
        #expect(loaded.runtime?.id == "cloudflared-2026.9.3")
        #expect(loaded.tunnels.first?.id == UUID(uuidString: "32394787-9B89-41AE-A065-57520475754A"))
        #expect(loaded.tunnels.first?.siteID == nil)
        #expect(loaded.tunnels.first?.routing == .cloudflare)
        try store.save(loaded)
        #expect(text(layout.settingsFile) == Self.golden)
        #expect(text(layout.previousSettingsFile) == Self.golden)
    }

    /// `golden` with `"routing" : "local"`, the only key that local routing adds.
    static let goldenLocal = golden.replacingOccurrences(
        of: "\"restartOnFailure\" : true,\n", with: "\"restartOnFailure\" : true,\n      \"routing\" : \"local\",\n")

    @Test func localRoutingSavesTheExactBytes() throws {
        let folder = try TemporaryDirectory(" tunnels")
        defer { folder.remove() }
        let store = TunnelStore(layout: folder.layout)
        var configuration = try JSONDecoder().decode(TunnelConfiguration.self, from: Data(Self.golden.utf8))
        configuration.tunnels[0].routing = .local
        try store.save(configuration)
        #expect(text(folder.layout.settingsFile) == Self.goldenLocal)
        #expect(try store.load() == configuration)
    }

    /// An explicit default loads as Cloudflare routing, and Save omits it, as earlier builds wrote.
    @Test func anExplicitCloudflareRoutingLoadsAndSavesWithoutTheKey() throws {
        let folder = try TemporaryDirectory(" tunnels")
        defer { folder.remove() }
        try OwnedDirectory.create(folder.layout.root)
        let explicit = Self.goldenLocal.replacingOccurrences(of: "\"local\"", with: "\"cloudflare\"")
        try AtomicFile.write(Data(explicit.utf8), to: folder.layout.settingsFile)
        let store = TunnelStore(layout: folder.layout)
        let loaded = try store.load()
        #expect(loaded.tunnels.first?.routing == .cloudflare)
        try store.save(loaded)
        #expect(text(folder.layout.settingsFile) == Self.golden)
    }

    /// A routing value from a later build cannot be read. The file stays as it is.
    @Test func anUnknownRoutingValueIsCorruptAndPreserved() throws {
        let folder = try TemporaryDirectory(" tunnels")
        defer { folder.remove() }
        try OwnedDirectory.create(folder.layout.root)
        let later = Self.goldenLocal.replacingOccurrences(of: "\"local\"", with: "\"hybrid\"")
        try AtomicFile.write(Data(later.utf8), to: folder.layout.settingsFile)
        #expect {
            try TunnelStore(layout: folder.layout).load()
        } throws: { error in
            (error as? JerdError)?.kind == .corrupt
        }
        #expect(text(folder.layout.settingsFile) == later)
    }

    /// The hand-written decoder keeps every key of earlier builds required.
    @Test(arguments: ["hostname", "id", "metricsPort", "name", "restartOnFailure", "startOnLaunch"])
    func everyRequiredKeyOfEarlierBuildsStaysRequired(_ key: String) throws {
        let line = try #require(Self.golden.split(separator: "\n").first { $0.contains("\"\(key)\" :") })
        let missing = Self.golden.replacingOccurrences(of: line + "\n", with: "")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TunnelConfiguration.self, from: Data(missing.utf8))
        }
    }

    /// Settings that an earlier build wrote with an IP address as hostname. That build accepted it;
    /// the current Save refuses it.
    static let goldenAddressHostname = """
        {
          "schemaVersion" : 1,
          "tunnels" : [
            {
              "hostname" : "10.0.0.1",
              "id" : "32394787-9B89-41AE-A065-57520475754A",
              "metricsPort" : 20241,
              "name" : "Office",
              "restartOnFailure" : true,
              "startOnLaunch" : true
            }
          ]
        }
        """

    /// Regression test: the stricter hostname rule made such a file unreadable, and
    /// every tunnel was blocked. It now loads, saves to the same bytes, and asks for an edit.
    @Test func earlierSettingsWithAnAddressHostnameLoadAndAskForAnEdit() async throws {
        let folder = try TemporaryDirectory(" tunnels")
        defer { folder.remove() }
        let layout = folder.layout
        try OwnedDirectory.create(layout.root)
        try AtomicFile.write(Data(Self.goldenAddressHostname.utf8), to: layout.settingsFile)
        let store = TunnelStore(layout: layout)
        let loaded = try store.load()
        try store.save(loaded)
        #expect(text(layout.settingsFile) == Self.goldenAddressHostname)
        let secrets = FakeSecretStore()
        let supervisor = TunnelSupervisor(layout: layout, secrets: secrets, connector: FakeConnector())
        let configuration = try await supervisor.load()
        let old = try #require(configuration.tunnels.first)
        await secrets.set(TokenSamples.valid, id: old.id)
        #expect(await supervisor.snapshots().first?.settingsIssue == TunnelMessage.addressHostname)
        await #expect(throws: JerdError.invalid(TunnelMessage.addressHostname)) { try await supervisor.save(old) }
        let other = TunnelRegistration(name: "Other", hostname: "other.example.com", metricsPort: 20_242)
        try await supervisor.save(other, token: TokenSamples.other)
        var fixed = old
        fixed.hostname = "office.example.com"
        try await supervisor.save(fixed)
        #expect(await supervisor.snapshots().allSatisfy { $0.settingsIssue == nil })
    }

    @Test func anAbsentFileLoadsAsEmptySettingsWithoutWriting() throws {
        let folder = try TemporaryDirectory(" tunnels")
        defer { folder.remove() }
        #expect(try TunnelStore(layout: folder.layout).load() == TunnelConfiguration())
        #expect(FileProbe.presence(at: folder.layout.settingsFile) == .absent)
    }

    @Test(arguments: [
        "", "not-json", #"{"schemaVersion":999,"tunnels":[]}"#, #"{"schemaVersion":1}"#,
        #"{"schemaVersion":1,"tunnels":[{"id":"32394787-9B89-41AE-A065-57520475754A","name":"A"}]}"#,
    ])
    func corruptSettingsArePreservedOnLoadAndSave(_ bytes: String) throws {
        let folder = try TemporaryDirectory(" tunnels")
        defer { folder.remove() }
        let layout = folder.layout
        try OwnedDirectory.create(layout.root)
        try AtomicFile.write(Data(bytes.utf8), to: layout.settingsFile)
        let store = TunnelStore(layout: layout)
        let error = try #require(throws: JerdError.self) { try store.load() }
        #expect(error.kind == .corrupt)
        #expect(error.message.hasPrefix("Cannot read tunnel settings. The file was preserved."))
        #expect(throws: JerdError.self) { try store.save(TunnelConfiguration()) }
        #expect(text(layout.settingsFile) == bytes)
    }

    @Test func requiredKeysMatchTheEarlierFormat() throws {
        let missingRestart = #"""
            {"schemaVersion":1,"tunnels":[{"hostname":"a.example.com","id":"32394787-9B89-41AE-A065-57520475754A",
            "metricsPort":20241,"name":"A","startOnLaunch":false}]}
            """#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TunnelConfiguration.self, from: Data(missingRestart.utf8))
        }
        let minimal = #"{"schemaVersion":1,"tunnels":[]}"#
        #expect(try JSONDecoder().decode(TunnelConfiguration.self, from: Data(minimal.utf8)) == TunnelConfiguration())
    }

    @Test func duplicateIDsOrMetricsPortsCannotBeSaved() throws {
        let folder = try TemporaryDirectory(" tunnels")
        defer { folder.remove() }
        let one = TunnelRegistration(name: "One", hostname: "one.example.com")
        let two = TunnelRegistration(name: "Two", hostname: "two.example.com")
        let store = TunnelStore(layout: folder.layout)
        for tunnels in [[one, two], [one, one]] {
            #expect(throws: JerdError.invalid(TunnelMessage.invalidConfiguration)) {
                try store.save(TunnelConfiguration(tunnels: tunnels))
            }
        }
        #expect(FileProbe.presence(at: folder.layout.settingsFile) == .absent)
    }

    @Test func moreThanOneHundredTunnelsCannotBeSaved() {
        let tunnels = (0...100).map {
            TunnelRegistration(name: "T\($0)", hostname: "t\($0).example.com", metricsPort: UInt16(20_000 + $0))
        }
        #expect(throws: JerdError.invalid(TunnelMessage.invalidConfiguration)) {
            try TunnelConfiguration(tunnels: tunnels).validate()
        }
    }

    @Test(arguments: [
        ("", "1.0.0", "/bin"), ("../x", "1.0.0", "/bin"), ("id", "1.0 0", "/bin"), ("id", "1.0.0", "relative"),
        ("id", "1.0.0", "/bad\npath"), (".", "1.0.0", "/bin"),
    ])
    func anUnsafeRuntimeRecordIsRefused(_ record: (String, String, String)) {
        let runtime = TunnelRuntime(id: record.0, version: record.1, path: record.2)
        #expect(throws: JerdError.invalid(TunnelMessage.invalidRuntime)) {
            try TunnelConfiguration(runtime: runtime).validate()
        }
    }

    /// Regression test: the picker and the installer gave one runtime three different ID forms.
    @Test func everyCheckedRuntimeGetsTheVersionID() throws {
        let runtime = TunnelRuntime(version: "2026.9.3", directory: URL(fileURLWithPath: "/opt/jerd/cloudflared"))
        #expect(runtime.id == "cloudflared-2026.9.3")
        #expect(runtime.executable.path == "/opt/jerd/cloudflared/cloudflared")
        try runtime.validate()
    }
}
