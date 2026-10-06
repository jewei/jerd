import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import JerdUI
import JerdWeb
import Testing

@testable import JerdLive

@Suite("Live runtime inventory")
struct LiveRuntimeInventoryTests {
    static let mail = SettingsSamples.build(.mailpit, version: "1.31.3", digest: "m1")
    static let rustfs = SettingsSamples.build(.rustfs, version: "1.0.0", digest: "r1")
    static let composer = SettingsSamples.build(.composer, version: "2.10.3", digest: "c1", executable: "composer.phar")
    static let lzma = SupportLibrary(
        library: URL(fileURLWithPath: "/nonexistent/liblzma.5.dylib"), license: URL(fileURLWithPath: "/nonexistent/XZ"))

    static func release(_ build: ManagedRuntime) -> RuntimeRelease {
        RuntimeRelease(
            kind: build.kind, version: build.releaseVersion, artifact: .composerPackage("x"),
            archiveSHA256: build.archiveSHA256, releasePage: URL(string: "https://example.invalid")!)
    }

    func inventory(
        _ installer: FakeManagedInstaller, owners: RecordingRuntimeOwners, sites: RecordingSiteChanges = .init()
    ) -> LiveRuntimeInventory {
        LiveRuntimeInventory(
            catalog: installer, installer: installer, owners: owners,
            activator: RuntimeActivator(owners: owners, sites: sites, inspector: FakeExecutableInspector()))
    }

    @Test func theSnapshotSkipsUnusableFoldersAndListsBuildsInUse() async throws {
        let installer = FakeManagedInstaller(
            [Self.mail, Self.rustfs], unusable: [.unusable(folder: "bad", reason: "receipt")])
        let owners = RecordingRuntimeOwners(records: RuntimeRecords(mail: RuntimeActivator.mailRuntime(Self.mail)))

        let snapshot = try await inventory(installer, owners: owners).snapshot()

        #expect(snapshot.builds == [RuntimeRecords.installedBuild(Self.mail)])
        #expect(snapshot.versions[.mailpit] == ["1.31.3"])
    }

    @Test func checkReadsTheCatalog() async {
        let installer = FakeManagedInstaller()
        let check = await inventory(installer, owners: RecordingRuntimeOwners()).check(.redis)

        #expect(check.kind == .redis)
        #expect(await installer.checked == [.redis])
    }

    @Test func rustFSInstallsWithTheBundledXZLibrary() async throws {
        let installer = FakeManagedInstaller([Self.rustfs])
        let owners = RecordingRuntimeOwners(lzma: Self.lzma)

        let build = try await inventory(installer, owners: owners).install(Self.release(Self.rustfs)) { _ in }

        #expect(build == RuntimeRecords.installedBuild(Self.rustfs))
        #expect(await installer.tools.map(\.lzma) == [Self.lzma])
        #expect(await owners.calls == [.lzma])
    }

    @Test func composerInstallsWithTheDefaultPHPAndTheSelectedComposer() async throws {
        let php = SettingsSamples.php("/nonexistent/php")
        let records = RuntimeRecords(sites: AppConfiguration(runtimes: [php], defaultRuntimeID: php.id))
        let installer = FakeManagedInstaller([Self.composer])

        _ = try await inventory(installer, owners: RecordingRuntimeOwners(records: records))
            .install(Self.release(Self.composer)) { _ in }

        let tools = try #require(await installer.tools.first)
        #expect(tools.phpCLI == URL(fileURLWithPath: "/nonexistent/php"))
        #expect(tools.lzma == nil)
    }

    @Test func otherKindsInstallWithoutReadingAnyRecord() async throws {
        let installer = FakeManagedInstaller([Self.mail])
        let owners = RecordingRuntimeOwners(lzma: Self.lzma)

        _ = try await inventory(installer, owners: owners).install(Self.release(Self.mail)) { _ in }

        #expect(await installer.tools.map(\.lzma) == [nil])
        #expect(await owners.calls.isEmpty)
    }

    @Test func activateFindsTheListedBuildAndHandsItToItsOwner() async throws {
        let installer = FakeManagedInstaller([Self.mail])
        let owners = RecordingRuntimeOwners()

        try await inventory(installer, owners: owners).activate(
            RuntimeRecords.installedBuild(Self.mail), useAsDefault: true)

        #expect(await owners.calls == [.mail(RuntimeActivator.mailRuntime(Self.mail))])
    }

    @Test func activateRefusesABuildThatIsNoLongerInstalled() async {
        let missing = InstalledBuild(kind: .mailpit, version: "1.31.3", releaseVersion: "1.31.3", archiveSHA256: "zz")

        await #expect(throws: JerdError.self) {
            try await inventory(FakeManagedInstaller([Self.mail]), owners: RecordingRuntimeOwners())
                .activate(missing, useAsDefault: true)
        }
    }

    @Test func aBuildMatchesOnlyItsKindReleaseAndDigest() {
        let listing: [ManagedRuntimeListing] = [.runtime(Self.mail), .runtime(Self.rustfs)]
        let wanted = RuntimeRecords.installedBuild(Self.rustfs)

        #expect(LiveRuntimeInventory.managedRuntime(for: wanted, in: listing) == Self.rustfs)
        #expect(
            LiveRuntimeInventory.managedRuntime(
                for: InstalledBuild(kind: .rustfs, version: "1.0.0", releaseVersion: "1.0.0", archiveSHA256: "other"),
                in: listing) == nil)
    }

    @Test func stagingCleanupUsesTheOneInstaller() async {
        let installer = FakeManagedInstaller()

        let removed = await inventory(installer, owners: RecordingRuntimeOwners()).removeAbandonedStaging()

        #expect(removed == [".staging-1"])
        #expect(await installer.stagingCleanups == 1)
    }
}
