import Foundation
import JerdManifest
import JerdRuntimes
import JerdServiceKit
import JerdStorage
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("RustFS on demand")
@MainActor
struct StorageRuntimeInstallTests {
    /// An app at first launch: no RustFS yet, and the pinned RustFS on offer.
    private func launched(
        behavior: InstallBehavior = .succeed, offer: StorageRuntimeOffer? = SampleServices.storageOffer,
        databases: InMemoryDatabases = InMemoryDatabases(), runtimes: InMemoryRuntimeInventory? = nil
    ) async -> (AppFixture, InMemoryStorage) {
        let storage = InMemoryStorage()
        await storage.configure {
            $0.offer = offer
            $0.installBehavior = behavior
        }
        let fixture = AppFixture(
            runtimes: runtimes ?? InMemoryRuntimeInventory(inventory: SampleData.inventory),
            services: InMemoryServicePorts(databases: databases, storage: storage, mail: InMemoryMail()))
        await fixture.state.launch()
        return (fixture, storage)
    }

    private static let waiting = InstallBehavior.suspend(
        RuntimeInstallProgress(
            RuntimePipeline.downloadMessage("RustFS 1.0.0", fraction: 0.4, size: .exact(87_018_416)), 0.4))

    @Test("First launch downloads nothing and offers RustFS on the page and the card")
    func firstLaunchOffersRustFS() async {
        let (fixture, storage) = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        #expect(model.runtimeOffer == SampleServices.storageOffer)
        #expect(await storage.calls == ["load"])
        #expect(model.canInstallRuntime && model.canStart && model.startInstallsRuntime)
        #expect(!model.canAddBucket)
        let summary = model.summary
        #expect(summary.summary == "RustFS is not installed. Start downloads it (87\u{00A0}MB).")
        #expect(summary.actions.map(\.title) == ["Start"] && summary.actions.allSatisfy(\.isEnabled))
        #expect(summary.actions.first?.spokenTitle == "Start Storage")
    }

    @Test("Install asks first, then installs and registers RustFS without a start")
    func installAfterConfirmation() async {
        let (fixture, storage) = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        model.requestRuntimeInstall()
        #expect(
            model.pendingRuntimeInstall
                == StorageRuntimeRequest(offer: SampleServices.storageOffer, startsStorage: false))
        #expect(await storage.calls == ["load"])
        await model.confirmRuntimeInstall()?.value
        #expect(await storage.calls == ["load", "install rustfs"])
        #expect(model.hasRuntime && model.runtimeInstallation == nil && model.runtimeNotice == nil)
        // An installed RustFS is not offered again.
        model.requestRuntimeInstall()
        #expect(model.pendingRuntimeInstall == nil)
    }

    @Test("Start without RustFS installs it first, then starts storage, in one flow")
    func startInstallsFirst() async {
        let (fixture, storage) = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        #expect(model.start() == nil)
        #expect(model.pendingRuntimeInstall?.startsStorage == true)
        #expect(await storage.calls == ["load"])
        await model.confirmRuntimeInstall()?.value
        await waitUntil { model.state.isRunning }
        #expect(await storage.calls == ["load", "install rustfs", "start"])
    }

    @Test("The card and the menu bar ask on the Storage page in the front window")
    func cardRequestShowsTheStoragePage() async throws {
        let (fixture, _) = await launched()
        defer { fixture.removeDefaults() }
        let state = fixture.state
        state.navigation.show(.dashboard(.overview))
        let before = fixture.shell.windowRequests
        try #require(state.storage.summary.actions.first).perform()
        #expect(state.navigation.section == .storage)
        #expect(fixture.shell.windowRequests == before + 1)
        #expect(state.storage.pendingRuntimeInstall?.startsStorage == true)
    }

    @Test("Progress shows in bytes; Cancel installs nothing and says so")
    func cancelInstallsNothing() async {
        let (fixture, storage) = await launched(behavior: Self.waiting)
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        model.requestRuntimeInstall(startsStorage: true)
        let task = model.confirmRuntimeInstall()
        await waitUntil { model.runtimeInstallation?.progress != nil }
        #expect(model.runtimeInstallation?.message == "Downloading RustFS 1.0.0… 34.8\u{00A0}MB of 87\u{00A0}MB")
        #expect(model.status.label == "Installing…")
        #expect(model.summary.summary == model.runtimeInstallation?.message)
        #expect(!model.canStart && !model.canInstallRuntime && model.isBusy)
        model.cancelRuntimeInstall()
        await task?.value
        #expect(model.runtimeNotice == StorageRuntimeNotice(message: StorageRuntimeCopy.cancelled, isFailure: false))
        #expect(!model.hasRuntime && model.runtimeInstallation == nil)
        #expect(await storage.calls == ["load", "install rustfs"])
    }

    @Test("A failed install shows the reason once, starts nothing, and can be dismissed")
    func failureShowsTheReason() async {
        let offline = "Jerd cannot reach the download server. Check the network connection, then try again."
        let (fixture, storage) = await launched(behavior: .fail(offline))
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        model.requestRuntimeInstall(startsStorage: true)
        await model.confirmRuntimeInstall()?.value
        #expect(model.runtimeNotice == StorageRuntimeNotice(message: offline, isFailure: true))
        #expect(model.operation == .idle)
        #expect(await storage.calls == ["load", "install rustfs"])
        model.dismissRuntimeNotice()
        #expect(model.runtimeNotice == nil && model.canInstallRuntime)
    }

    @Test("Quit cancels a running install before its final rename and clears a waiting request")
    func quitCancelsTheInstall() async {
        let (fixture, _) = await launched(behavior: Self.waiting)
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        model.requestRuntimeInstall()
        _ = model.confirmRuntimeInstall()
        await waitUntil { model.runtimeInstallation?.progress != nil }
        #expect(await model.shutdown())
        #expect(!model.hasRuntime && model.runtimeInstallation == nil)
        model.resumeAfterCancelledQuit()
        model.requestRuntimeInstall()
        #expect(model.pendingRuntimeInstall != nil)
        _ = await model.shutdown()
        #expect(model.pendingRuntimeInstall == nil)
    }

    @Test("An app without a pinned RustFS leads to Runtimes, as before")
    func noPinLeadsToRuntimes() async {
        let (fixture, _) = await launched(offer: nil)
        defer { fixture.removeDefaults() }
        let model = fixture.state.storage
        #expect(!model.canStart && !model.canInstallRuntime)
        #expect(model.summary.summary == "RustFS is not installed. Install it in Runtimes.")
    }

    @Test("Storage, Databases, and Runtimes wait for each other's install")
    func pagesWaitForEachOther() async throws {
        let databases = InMemoryDatabases()
        await databases.configure {
            $0.offers = SampleServices.offers
            $0.installBehavior = .suspend(RuntimeInstallProgress("Downloading MySQL 8.4.11…", 0.2))
        }
        let (fixture, _) = await launched(
            behavior: Self.waiting, databases: databases,
            runtimes: InMemoryRuntimeInventory(inventory: SampleData.onDemandInventory))
        defer { fixture.removeDefaults() }
        let state = fixture.state
        state.storage.requestRuntimeInstall()
        let storageTask = state.storage.confirmRuntimeInstall()
        await waitUntil { state.storage.runtimeInstallation?.progress != nil }
        let reason = "The Storage page is installing RustFS 1.0.0. Installs wait until it finishes."
        #expect(state.databases.runtimeInstallElsewhere?() == reason)
        #expect(state.runtimes.runtimeInstallElsewhere?() == reason)
        #expect(!state.databases.canInstallRuntime && !state.runtimes.canInstallRuntimes)
        state.storage.cancelRuntimeInstall()
        await storageTask?.value

        state.databases.requestRuntimeInstall(.mysql)
        let databasesTask = state.databases.confirmRuntimeInstall()
        await waitUntil { state.databases.runtimeInstallation?.progress != nil }
        #expect(!state.storage.canInstallRuntime && !state.storage.canStart)
        #expect(state.storage.startUnavailableReason?.hasPrefix("The Databases page is installing MySQL") == true)
        state.databases.cancelRuntimeInstall()
        await databasesTask?.value
        #expect(state.storage.canInstallRuntime)
    }

    @Test("The words: the size, the source, the space, the reuse, and the start")
    func installCopy() {
        let offer = SampleServices.storageOffer
        let install = StorageRuntimeRequest(offer: offer, startsStorage: false)
        let start = StorageRuntimeRequest(offer: offer, startsStorage: true)
        #expect(StorageRuntimeCopy.confirmationTitle(install) == "Install RustFS 1.0.0?")
        #expect(StorageRuntimeCopy.confirmTitle(install) == "Download and Install")
        #expect(StorageRuntimeCopy.confirmTitle(start) == "Download and Start")
        let message = StorageRuntimeCopy.confirmationMessage(install)
        #expect(message.contains("87\u{00A0}MB from github.com") && message.contains("reviewed checksum"))
        #expect(message.contains("310.6\u{00A0}MB of free disk space") && !message.contains("signature"))
        #expect(StorageRuntimeCopy.confirmationMessage(start).hasSuffix("Then Jerd starts storage."))
        #expect(StorageRuntimeCopy.notInstalledDetail(offer) == "Not installed. RustFS 1.0.0, 87\u{00A0}MB download.")

        let reused = StorageRuntimeOffer(
            versionLabel: "1.0.0", downloadSize: offer.downloadSize, source: offer.source,
            installedSize: offer.installedSize, reusesInstalledCopy: true)
        let reuse = StorageRuntimeRequest(offer: reused, startsStorage: false)
        #expect(StorageRuntimeCopy.confirmTitle(reuse) == "Install")
        #expect(
            StorageRuntimeCopy.confirmTitle(StorageRuntimeRequest(offer: reused, startsStorage: true))
                == "Install and Start")
        #expect(StorageRuntimeCopy.confirmationMessage(reuse).contains("Nothing is downloaded"))
        #expect(!StorageRuntimeCopy.confirmationMessage(reuse).contains("87"))
        #expect(StorageRuntimeCopy.notInstalledDetail(reused).contains("already on this Mac"))
        #expect(StorageRuntimeCopy.cardNotice(reused).contains("copy on this Mac"))
        #expect(reused.requiredSpace == 0 && offer.requiredSpace == 310_553_317)
    }

    @Test("Runtimes offers RustFS with the same words while it is not installed")
    func runtimesOffersRustFS() throws {
        let release = try #require(SampleData.onDemandReleases.first { $0.kind == .rustfs })
        #expect(SampleData.onDemandInventory.installableRelease(.rustfs) == release)
        #expect(
            RuntimeCopy.onDemandDetail(release)
                == "1.0.0, 87\u{00A0}MB download. Jerd checks it against its reviewed checksum.")
        let request = StorageRuntimeRequest(offer: SampleServices.storageOffer, startsStorage: false)
        #expect(
            RuntimeInstallCopy.confirmationMessage(release, reuses: false)
                == StorageRuntimeCopy.confirmationMessage(request))
    }
}
