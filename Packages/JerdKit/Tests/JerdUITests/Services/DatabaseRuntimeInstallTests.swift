import Foundation
import JerdDatabases
import JerdDesign
import JerdManifest
import JerdRuntimes
import JerdServiceKit
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Database runtimes on demand")
@MainActor
struct DatabaseRuntimeInstallTests {
    /// An app without database runtimes that offers every pinned engine.
    private func launched(
        configuration: DatabaseConfiguration = DatabaseConfiguration(), behavior: InstallBehavior = .succeed
    ) async -> (AppFixture, InMemoryDatabases) {
        let databases = InMemoryDatabases(configuration: configuration)
        await databases.configure {
            $0.offers = SampleServices.offers
            $0.installBehavior = behavior
        }
        let fixture = AppFixture(
            services: InMemoryServicePorts(databases: databases, storage: InMemoryStorage(), mail: InMemoryMail()))
        await fixture.state.launch()
        return (fixture, databases)
    }

    private static let waiting = InstallBehavior.suspend(RuntimeInstallProgress("Downloading MySQL 8.4.11…", 0.25))

    @Test("First launch offers every engine, downloads nothing, and the card offers Add Database")
    func firstLaunchOffersEveryEngine() async {
        let (fixture, databases) = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        #expect(model.availableEngines.isEmpty)
        #expect(model.addableEngines == DatabaseEngine.allCases)
        #expect(await databases.calls == ["load"])
        let summary = model.summary
        #expect(!summary.summary.contains("Runtimes"))
        #expect(summary.actions.map(\.title) == ["Add Database…"] && summary.actions.allSatisfy(\.isEnabled))
        #expect(model.newItemAction?.isEnabled == true)
    }

    @Test("An installed engine is not offered again")
    func installedEngineIsNotOffered() async {
        let (fixture, _) = await launched(configuration: DatabaseConfiguration(runtimes: [SampleServices.mysql]))
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        #expect(model.offer(for: .mysql) == nil)
        #expect(model.offer(for: .redis)?.versionLabel == "8.8.3")
        model.requestRuntimeInstall(.mysql)
        #expect(model.pendingRuntimeInstall == nil)
    }

    @Test("Install asks first, then installs and registers the engine")
    func installAfterConfirmation() async {
        let (fixture, databases) = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.requestRuntimeInstall(.redis)
        #expect(model.pendingRuntimeInstall?.engine == .redis)
        #expect(await databases.calls == ["load"])
        await model.confirmRuntimeInstall()?.value
        #expect(await databases.calls.contains("install redis"))
        #expect(model.availableEngines == [.redis])
        #expect(model.runtimeInstallation == nil && model.runtimeNotice == nil)
    }

    @Test("A failed installation names the engine and the reason")
    func failureShowsTheReason() async {
        let offline = "Jerd cannot reach the download server. Check the network connection, then try again."
        let (fixture, _) = await launched(behavior: .fail(offline))
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.requestRuntimeInstall(.mysql)
        await model.confirmRuntimeInstall()?.value
        #expect(model.runtimeNotice == DatabaseRuntimeNotice(engine: .mysql, message: offline, isFailure: true))
        #expect(model.availableEngines.isEmpty && model.runtimeInstallation == nil)
        model.dismissRuntimeNotice()
        #expect(model.runtimeNotice == nil)
    }

    @Test("Cancel stops the installation, installs nothing, and says so")
    func cancelStopsTheInstallation() async {
        let (fixture, _) = await launched(behavior: Self.waiting)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.requestRuntimeInstall(.mysql)
        let task = model.confirmRuntimeInstall()
        await waitUntil { model.runtimeInstallation?.progress != nil }
        #expect(model.summary.status.label == "Installing MySQL…")
        #expect(!model.canInstallRuntime && model.isBusy)
        model.cancelRuntimeInstall()
        await task?.value
        #expect(model.runtimeInstallation == nil && model.availableEngines.isEmpty)
        #expect(model.runtimeNotice?.isFailure == false)
    }

    @Test("Add for an engine without a runtime installs it, then creates and starts the service")
    func addInstallsFirst() async throws {
        let (fixture, databases) = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.beginAdd(.redis)
        await waitUntil { model.editor?.portText.isEmpty == false }
        #expect(model.editorRuntimeOffer?.engine == .redis)
        #expect(model.canSaveEditor)
        await model.saveEditor()?.value
        await waitUntil { model.busyServices.isEmpty && model.services.count == 1 }
        let service = try #require(model.services.first)
        #expect(model.runtime(of: service)?.engine == .redis)
        let calls = await databases.calls
        #expect(calls.firstIndex(of: "install redis") ?? 99 < calls.firstIndex { $0.hasPrefix("add ") } ?? 0)
        #expect(calls.contains { $0.hasPrefix("start ") })
        #expect(model.sheet == nil)
    }

    @Test("A failed installation in Add stays in the sheet and creates nothing")
    func addInstallFailureStaysInSheet() async {
        let full = "There is not enough free disk space to install this runtime. Free some space, then try again."
        let (fixture, databases) = await launched(behavior: .fail(full))
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.beginAdd(.mysql)
        await waitUntil { model.editor?.portText.isEmpty == false }
        await model.saveEditor()?.value
        #expect(model.editorOperation == .failed(message: full))
        #expect(model.sheet == .editor && model.services.isEmpty)
        #expect(!(await databases.calls).contains { $0.hasPrefix("add ") })
    }

    @Test("Cancel in the Add sheet stops the installation and creates nothing")
    func cancelAddStopsTheInstallation() async {
        let (fixture, databases) = await launched(behavior: Self.waiting)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.beginAdd(.mysql)
        await waitUntil { model.editor?.portText.isEmpty == false }
        let task = model.saveEditor()
        await waitUntil { model.runtimeInstallation?.addsService == true }
        model.closeEditor()
        await task?.value
        #expect(model.runtimeInstallation == nil && model.services.isEmpty)
        #expect(model.editorOperation == .idle && model.operation == .idle)
        #expect(!(await databases.calls).contains { $0.hasPrefix("add ") })
    }

    @Test("Quit cancels a running installation instead of waiting for the download")
    func quitCancelsTheInstallation() async {
        let (fixture, _) = await launched(behavior: Self.waiting)
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.requestRuntimeInstall(.postgresql)
        model.confirmRuntimeInstall()
        await waitUntil { model.runtimeInstallation?.progress != nil }
        #expect(await model.shutdown())
        #expect(model.runtimeInstallation == nil && model.availableEngines.isEmpty)
    }

    @Test("A draft without a runtime is valid only when Save installs the engine first")
    func draftRuleForAMissingRuntime() {
        let draft = DatabaseDraft.add(.mysql, in: DatabaseConfiguration())
        #expect(draft.issue(in: DatabaseConfiguration()) == "Install a MySQL runtime in Runtimes first.")
        #expect(draft.issue(in: DatabaseConfiguration(), installsRuntime: true) == nil)
    }

    @Test("The install words name the size, the source, and the checks")
    func installCopy() throws {
        let mysql = try #require(SampleServices.offers.first { $0.engine == .mysql })
        let redis = try #require(SampleServices.offers.first { $0.engine == .redis })
        let postgres = try #require(SampleServices.offers.first { $0.engine == .postgresql })
        #expect(DatabaseRuntimeCopy.installTitle(.mysql) == "Install MySQL…")
        #expect(DatabaseRuntimeCopy.confirmationTitle(mysql) == "Install MySQL 8.4.11?")
        #expect(DatabaseRuntimeCopy.confirmationTitle(postgres) == "Install PostgreSQL (Postgres.app 2.9.6)?")
        let message = DatabaseRuntimeCopy.confirmationMessage(mysql)
        #expect(message.contains("168\u{00A0}MB") && message.contains("cdn.mysql.com"))
        #expect(message.contains("publisher signature"))
        #expect(DatabaseRuntimeCopy.confirmationMessage(redis).contains("Xcode Command Line Tools"))
        #expect(DatabaseRuntimeCopy.addTitle(installsRuntime: true) == "Install and Create")
        #expect(DatabaseRuntimeCopy.addTitle(installsRuntime: false) == "Create and Start")
    }

    @Test("Runtimes offers a pinned release only while its kind has no installed version")
    func runtimesOffersOnDemandReleases() throws {
        let release = try #require(SampleData.onDemandReleases.first)
        var snapshot = RuntimeInventorySnapshot(onDemand: [release])
        #expect(snapshot.installableRelease(.mysql) == release)
        #expect(snapshot.installableRelease(.redis) == nil)
        snapshot.versions[.mysql] = ["8.4.3"]
        #expect(snapshot.installableRelease(.mysql) == nil)
        #expect(RuntimeCopy.onDemandDetail(release).hasPrefix("8.4.11, 168"))
    }
}
