import Foundation
import JerdFoundation
import JerdMail
import JerdManifest
import JerdRuntimes
import JerdTestSupport
import JerdUI
import Testing

@testable import JerdLive

@Suite("Mailpit on demand")
struct MailRuntimeInstallerTests {
    static let layout = DataLayout(root: URL(fileURLWithPath: "/nonexistent/Jerd"))
    static let mailpit = DatabaseRuntimeInstallerTests.pinned(
        .mailpit, "1.31.3", digest: "f72a",
        link: "https://github.com/axllent/mailpit/releases/download/v1.31.3/mailpit-darwin-arm64.tar.gz",
        size: 9_848_192, installedSize: 26_328_126)
    static let mailpitBuild = SettingsSamples.build(.mailpit, version: "1.31.3", digest: "f72a")
    /// The Mailpit that an earlier copy embedded and installed in `mail-runtimes/`.
    static let earlier = ReusablePayload(
        id: "mailpit-1.31.3-arm64-0123456789abcdef", kind: .mailpit, version: "1.31.3",
        directory: URL(fileURLWithPath: "/nonexistent/Jerd/mail-runtimes/mailpit-1.31.3-arm64-0123456789abcdef"))

    private func installer(
        _ releases: FakeOnDemandReleases = FakeOnDemandReleases(list: [Self.mailpit]),
        installer: FakeManagedInstaller = FakeManagedInstaller(),
        manager: RecordingMailManager = RecordingMailManager(), free: Int64? = nil
    ) -> MailRuntimeInstaller {
        MailRuntimeInstaller(
            flow: OnDemandInstallFlow(
                releases: releases, installer: installer, layout: Self.layout, freeSpace: FakeFreeSpace(bytes: free)),
            manager: manager)
    }

    @Test("The offer names the pinned version, the sizes, and the source")
    func offerMapsThePin() async {
        #expect(
            await installer().offer()
                == ServiceRuntimeOffer(
                    name: "Mailpit", versionLabel: "1.31.3", downloadSize: 9_848_192, source: "github.com",
                    installedSize: 26_328_126))
        #expect(await installer().offer()?.title == "Mailpit 1.31.3")
        #expect(await installer().offer()?.requiredSpace == 9_848_192 + 26_328_126)
    }

    @Test("Another kind, an inexact size, no pin, or a bad catalog offers nothing")
    func otherReleasesOfferNothing() async {
        let limited = RuntimeRelease(
            kind: .mailpit, version: "1.31.3",
            artifact: .archive(Self.mailpit.artifact.downloadURL!, size: .atMost(10)), archiveSHA256: "f72a",
            releasePage: Self.mailpit.releasePage)
        #expect(MailRuntimeInstaller.offer(StorageRuntimeInstallerTests.rustfs) == nil)
        #expect(MailRuntimeInstaller.offer(limited) == nil)
        #expect(StorageRuntimeInstaller.offer(Self.mailpit) == nil)
        #expect(await installer(FakeOnDemandReleases(list: [StorageRuntimeInstallerTests.rustfs])).offer() == nil)
        #expect(await installer(FakeOnDemandReleases(failure: .invalid("bad catalog"))).offer() == nil)
    }

    @Test("Install downloads and builds the pin, then registers it under a new ID")
    func installBuildsAndRegisters() async throws {
        let manager = RecordingMailManager()
        let managed = FakeManagedInstaller(downloads: [Self.mailpitBuild])
        let runtime = try await installer(installer: managed, manager: manager).install { _ in }
        #expect(runtime == RuntimeActivator.mailRuntime(Self.mailpitBuild))
        // Mailpit needs no preparation tools.
        let tools = await managed.tools
        #expect(tools.count == 1 && tools.allSatisfy { $0.lzma == nil && $0.phpCLI == nil })
        // Only the runtime record changes: no start, no test email, no port edit.
        #expect(await manager.calls == ["register \(runtime.id)"])
    }

    @Test("A verified Mailpit of an earlier copy is registered again; nothing is downloaded")
    func reusesAnEarlierPayload() async throws {
        let manager = RecordingMailManager()
        let managed = FakeManagedInstaller()
        let releases = FakeOnDemandReleases(list: [Self.mailpit], reusable: Self.earlier)
        let installer = installer(releases, installer: managed, manager: manager, free: 0)
        #expect(await installer.offer()?.reusesInstalledCopy == true)
        #expect(await installer.offer()?.requiredSpace == 0)
        let messages = ProgressLog()
        let runtime = try await installer.install { messages.append($0.message) }
        #expect(runtime == MailRuntime(id: Self.earlier.id, version: "1.31.3", path: Self.earlier.directory.path))
        #expect(messages.all == ["Using the Mailpit 1.31.3 that is already on this Mac."])
        #expect(await managed.tools.isEmpty)
        #expect(await manager.calls == ["register \(runtime.id)"])
    }

    @Test("Too little free space stops the install before the download")
    func tooLittleFreeSpaceStops() async {
        let managed = FakeManagedInstaller()
        let manager = RecordingMailManager()
        await #expect {
            try await installer(installer: managed, manager: manager, free: 10_000_000).install { _ in }
        } throws: { error in
            (error as? JerdError)?.message.contains("36.2\u{00A0}MB") == true
        }
        #expect(await managed.tools.isEmpty)
        #expect(await manager.calls.isEmpty)
    }

    @Test("A failed or cancelled build registers nothing")
    func failedBuildRegistersNothing() async {
        let manager = RecordingMailManager()
        // The fake has no build of the release, so its install stops as a cancel does.
        await #expect(throws: CancellationError.self) { try await installer(manager: manager).install { _ in } }
        #expect(await manager.calls.isEmpty)
        let none = installer(FakeOnDemandReleases(list: []), manager: manager)
        await #expect(throws: JerdError.self) { try await none.install { _ in } }
        await #expect(throws: JerdError.self) {
            try await installer(manager: manager).install(StorageRuntimeInstallerTests.rustfs) { _ in }
        }
        #expect(await manager.calls.isEmpty)
    }

    @Test("Runtimes › Install… of Mailpit uses the same flow, and activation has nothing left to do")
    func runtimesInstallUsesTheOneFlow() async throws {
        let managed = FakeManagedInstaller()
        let manager = RecordingMailManager()
        let registered = MailRuntime(id: Self.earlier.id, version: "1.31.3", path: Self.earlier.directory.path)
        let owners = RecordingRuntimeOwners(records: RuntimeRecords(mail: registered))
        let inventory = LiveRuntimeInventory(
            catalog: managed, installer: managed, owners: owners,
            activator: RuntimeActivator(
                owners: owners, sites: RecordingSiteChanges(), inspector: FakeExecutableInspector()),
            mail: installer(
                FakeOnDemandReleases(list: [Self.mailpit], reusable: Self.earlier), installer: managed,
                manager: manager, free: 0))
        let snapshot = try await inventory.snapshot()
        #expect(snapshot.onDemand == [Self.mailpit] && snapshot.reusableOnDemand == [.mailpit])
        let build = try await inventory.install(Self.mailpit) { _ in }
        #expect(build.kind == .mailpit && build.version == "1.31.3")
        #expect(await manager.calls == ["register \(registered.id)"])
        #expect(await managed.tools.isEmpty)
        try await inventory.activate(build, useAsDefault: true)
        #expect(await owners.calls.isEmpty)
    }

    @Test("The live Mail port and Runtimes share the one installer of the domain")
    func liveDomainSharesOneInstaller() throws {
        let folder = try TemporaryDirectory("mail-installer")
        defer { folder.remove() }
        let domain = LiveDomain(
            configuration: LiveConfiguration(
                layout: folder.layout, appBundle: folder.url, resources: folder.url, appVersion: "test"))
        let port = LiveMailPort(domain: domain)
        let inventory = LiveRuntimeInventory(domain: domain)
        let portInstaller = try #require(port.onDemand?.flow.installer as? RuntimeInstaller)
        let inventoryInstaller = try #require(inventory.mail?.flow.installer as? RuntimeInstaller)
        #expect(portInstaller === domain.runtimeInstaller && inventoryInstaller === domain.runtimeInstaller)
    }
}
