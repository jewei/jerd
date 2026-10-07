import Foundation
import JerdDatabases
import JerdFoundation
import JerdMail
import JerdManifest
import JerdRuntimes
import JerdStorage
import JerdTestSupport
import Testing

@testable import JerdLive

/// A new user has no RustFS and no Mailpit (the app installs them on demand). A RustFS, Mailpit, or
/// database release from Check for Runtime Updates must then become usable, not stay an unused build.
@Suite("Runtime updates without a saved runtime")
struct StorageRuntimeAdoptionTests {
    static let runtime = StorageRuntime(
        id: "rustfs-1.0.1-arm64-abc", version: "1.0.1", path: "/nonexistent/Jerd/runtime-updates/rustfs-1.0.1-arm64-abc"
    )

    @Test("Without a saved runtime the build is registered; with one it goes through the update")
    func adoptionRule() async throws {
        let empty = RecordingStorageManager()
        try await StorageRuntimeAdoption.adopt(Self.runtime, manager: empty)
        #expect(await empty.calls == ["register \(Self.runtime.id)"])

        var settings = StorageSettings()
        settings.runtime = StorageRuntime(id: "rustfs-1.0.0", version: "1.0.0", path: "/runtimes/rustfs")
        let saved = RecordingStorageManager(settings)
        try await StorageRuntimeAdoption.adopt(Self.runtime, manager: saved)
        #expect(await saved.calls == ["update \(Self.runtime.id)"])
    }

    @Test("Without a saved Mailpit the build is registered; with one it goes through the update")
    func mailAdoptionRule() async throws {
        let build = MailRuntime(
            id: "mailpit-1.31.4-arm64-abc", version: "1.31.4",
            path: "/nonexistent/Jerd/runtime-updates/mailpit-1.31.4-arm64-abc")
        let empty = RecordingMailManager()
        try await MailRuntimeAdoption.adopt(build, manager: empty)
        #expect(await empty.calls == ["register \(build.id)"])

        var settings = MailSettings()
        settings.runtime = MailRuntime(id: "mailpit-1.31.3", version: "1.31.3", path: "/runtimes/mailpit")
        let saved = RecordingMailManager(settings)
        try await MailRuntimeAdoption.adopt(build, manager: saved)
        #expect(await saved.calls == ["update \(build.id)"])
    }

    /// The live domain on a temporary data root, with the committed catalog in its bundle.
    private func domain(_ folder: TemporaryDirectory) throws -> LiveDomain {
        let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../../Runtimes/runtimes.json").standardizedFileURL
        _ = try folder.file("Resources/RuntimePayloads/runtimes.json", Data(contentsOf: catalog))
        return LiveDomain(
            configuration: LiveConfiguration(
                layout: folder.layout, appBundle: folder.url, resources: folder.path("Resources"),
                appVersion: "test"))
    }

    /// Installs `release` as a managed update (the fake has its build) and activates it.
    private func installChecked(_ release: RuntimeRelease, build: ManagedRuntime, domain: LiveDomain) async throws {
        let installer = FakeManagedInstaller([build])
        let owners = DomainRuntimeOwners(domain: domain)
        let inventory = LiveRuntimeInventory(
            catalog: installer, installer: installer, owners: owners,
            activator: RuntimeActivator(
                owners: owners, sites: RecordingSiteChanges(), inspector: FakeExecutableInspector()))
        let installed = try await inventory.install(release) { _ in }
        try await inventory.activate(installed, useAsDefault: true)
    }

    @Test("A checked RustFS release without a saved RustFS is registered and usable")
    func checkedRustFSIsRegistered() async throws {
        let folder = try TemporaryDirectory("checked-rustfs")
        defer { folder.remove() }
        let domain = try domain(folder)
        _ = try await domain.storage.load()
        let build = SettingsSamples.build(.rustfs, version: "1.0.1", digest: "abc")
        let release = DatabaseRuntimeInstallerTests.pinned(
            .rustfs, "1.0.1", digest: "abc", link: "https://github.com/rustfs/rustfs/releases/download/1.0.1/r.zip",
            size: 10)
        try await installChecked(release, build: build, domain: domain)
        let saved = await domain.storage.snapshot().settings
        #expect(saved.runtime == RuntimeActivator.storageRuntime(build))
        #expect(saved.buckets.isEmpty)
    }

    /// The live `MailManager` refuses an update without a saved runtime, so this fails if the
    /// activation calls the update directly.
    @Test("A checked Mailpit release without a saved Mailpit is registered and usable")
    func checkedMailpitIsRegistered() async throws {
        let folder = try TemporaryDirectory("checked-mailpit")
        defer { folder.remove() }
        let domain = try domain(folder)
        _ = try await domain.mail.load()
        let build = SettingsSamples.build(.mailpit, version: "1.31.4", digest: "abc")
        let release = DatabaseRuntimeInstallerTests.pinned(
            .mailpit, "1.31.4", digest: "abc",
            link: "https://github.com/axllent/mailpit/releases/download/v1.31.4/m.tar.gz", size: 10)
        try await installChecked(release, build: build, domain: domain)
        let saved = await domain.mail.snapshot().settings
        #expect(saved.runtime == RuntimeActivator.mailRuntime(build))
        // The registration chose the ports; the inbox folder is created only at the first start.
        #expect(FileProbe.presence(at: folder.layout.mail.inboxDirectory) == .absent)
    }

    @Test("A checked MySQL release for an engine without a runtime is registered")
    func checkedDatabaseIsRegistered() async throws {
        let folder = try TemporaryDirectory("checked-mysql")
        defer { folder.remove() }
        let domain = try domain(folder)
        _ = try await domain.databases.load()
        let build = SettingsSamples.build(.mysql, version: "8.4.12", digest: "def")
        let release = DatabaseRuntimeInstallerTests.pinned(
            .mysql, "8.4.12", digest: "def", link: "https://cdn.mysql.com/Downloads/MySQL-8.4/m.tar.gz", size: 10)
        try await installChecked(release, build: build, domain: domain)
        #expect(
            await domain.databases.snapshot().configuration.runtimes == [try RuntimeActivator.databaseRuntime(build)])
    }
}
