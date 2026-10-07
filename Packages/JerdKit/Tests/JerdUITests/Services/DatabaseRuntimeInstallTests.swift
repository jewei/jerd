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
    /// An app that installed its embedded Redis at first launch and offers MySQL and PostgreSQL.
    private func launched(
        configuration: DatabaseConfiguration = DatabaseConfiguration(runtimes: [SampleServices.redis]),
        behavior: InstallBehavior = .succeed
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

    @Test("First launch has Redis, offers MySQL and PostgreSQL, downloads nothing, and offers Add Database")
    func firstLaunchOffersTheOnDemandEngines() async {
        let (fixture, databases) = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        #expect(model.availableEngines == [.redis])
        #expect(model.offer(for: .redis) == nil)
        #expect(model.runtimeOffers.map(\.engine) == [.mysql, .postgresql])
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
        // The engine version, not the Postgres.app version, before the install.
        #expect(model.offer(for: .postgresql)?.versionLabel == "18.6")
        #expect(model.offer(for: .postgresql)?.title == "PostgreSQL 18.6")
        model.requestRuntimeInstall(.mysql)
        #expect(model.pendingRuntimeInstall == nil)
    }

    @Test("Install asks first, then installs and registers the engine")
    func installAfterConfirmation() async {
        let (fixture, databases) = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.requestRuntimeInstall(.postgresql)
        #expect(model.pendingRuntimeInstall?.engine == .postgresql)
        #expect(await databases.calls == ["load"])
        await model.confirmRuntimeInstall()?.value
        #expect(await databases.calls.contains("install postgresql"))
        #expect(model.availableEngines == [.postgresql, .redis])
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
        #expect(model.availableEngines == [.redis] && model.runtimeInstallation == nil)
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
        #expect(model.runtimeInstallation == nil && model.availableEngines == [.redis])
        #expect(model.runtimeNotice?.isFailure == false)
    }

    @Test("Add for an engine without a runtime installs it, then creates and starts the service")
    func addInstallsFirst() async throws {
        let (fixture, databases) = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.beginAdd(.postgresql)
        await waitUntil { model.editor?.portText.isEmpty == false }
        #expect(model.editorRuntimeOffer?.engine == .postgresql)
        #expect(model.canSaveEditor)
        await model.saveEditor()?.value
        await waitUntil { model.busyServices.isEmpty && model.services.count == 1 }
        let service = try #require(model.services.first)
        #expect(model.runtime(of: service)?.engine == .postgresql)
        #expect(model.runtime(of: service)?.version == "18.6")
        let calls = await databases.calls
        #expect(calls.firstIndex(of: "install postgresql") ?? 99 < calls.firstIndex { $0.hasPrefix("add ") } ?? 0)
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
        #expect(model.runtimeInstallation == nil && model.availableEngines == [.redis])
    }

    @Test("An open Add sheet takes a runtime that another path installed, and can save")
    func addSheetAdoptsARuntimeInstalledElsewhere() async throws {
        let (fixture, databases) = await launched()
        defer { fixture.removeDefaults() }
        let model = fixture.state.databases
        model.beginAdd(.mysql)
        await waitUntil { model.editor?.portText.isEmpty == false }
        #expect(model.editorRuntimeOffer?.engine == .mysql)
        // Runtimes, the page, or another sheet installs MySQL while the sheet is open.
        await databases.configure { $0.configuration.runtimes.append(SampleServices.mysql) }
        await model.refresh()
        #expect(model.editorRuntimeOffer == nil)
        #expect(model.editor?.runtimeID == SampleServices.mysql.id)
        #expect(model.canSaveEditor)
        await model.saveEditor()?.value
        await waitUntil { model.services.count == 1 }
        #expect(model.services.first?.runtimeID == SampleServices.mysql.id)
        #expect(!(await databases.calls).contains("install mysql"))
    }

    @Test("Each page waits while the other page installs a runtime")
    func pagesWaitForEachOther() async throws {
        let databases = InMemoryDatabases(configuration: DatabaseConfiguration(runtimes: [SampleServices.redis]))
        let waiting = Self.waiting
        await databases.configure {
            $0.offers = SampleServices.offers
            $0.installBehavior = waiting
        }
        let runtimes = InMemoryRuntimeInventory(
            inventory: SampleData.onDemandInventory, installBehavior: .suspend(RuntimeInstallProgress("…", 0.1)))
        let fixture = AppFixture(
            runtimes: runtimes,
            services: InMemoryServicePorts(databases: databases, storage: InMemoryStorage(), mail: InMemoryMail()))
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        let state = fixture.state
        await state.runtimes.load()
        let postgres = try #require(SampleData.onDemandReleases.last)
        let runtimesTask = state.runtimes.install(postgres)
        await waitUntil { state.runtimes.installation?.progress != nil }
        #expect(!state.databases.canInstallRuntime)
        state.databases.requestRuntimeInstall(.mysql)
        #expect(state.databases.pendingRuntimeInstall == nil)
        state.runtimes.cancelInstall()
        await runtimesTask?.value
        #expect(state.databases.canInstallRuntime)
        state.databases.requestRuntimeInstall(.mysql)
        let databasesTask = state.databases.confirmRuntimeInstall()
        await waitUntil { state.databases.runtimeInstallation?.progress != nil }
        #expect(!state.runtimes.canChangeRuntimes)
        state.databases.cancelRuntimeInstall()
        await databasesTask?.value
        #expect(state.runtimes.canChangeRuntimes)
    }

    @Test("Runtimes asks first before it installs a pinned engine, with the same words")
    func runtimesAsksFirst() async throws {
        let runtimes = InMemoryRuntimeInventory(inventory: SampleData.onDemandInventory)
        let fixture = AppFixture(runtimes: runtimes)
        defer { fixture.removeDefaults() }
        let model = fixture.state.runtimes
        await model.load()
        let mysql = try #require(SampleData.onDemandReleases.first)
        model.requestOnDemandInstall(mysql)
        #expect(model.pendingOnDemandInstall == mysql)
        #expect(await runtimes.installed.isEmpty)
        let message = RuntimeInstallCopy.confirmationMessage(mysql)
        #expect(message.contains("publisher signature") && message.contains("528.5\u{00A0}MB of free disk space"))
        await model.confirmOnDemandInstall()?.value
        #expect(await runtimes.installed == [mysql])
        // An installed kind is not offered again.
        model.requestOnDemandInstall(mysql)
        #expect(model.pendingOnDemandInstall == nil)
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
        let postgres = try #require(SampleServices.offers.first { $0.engine == .postgresql })
        #expect(DatabaseRuntimeCopy.installTitle(.mysql) == "Install MySQL…")
        #expect(DatabaseRuntimeCopy.confirmationTitle(mysql) == "Install MySQL 8.4.11?")
        #expect(DatabaseRuntimeCopy.confirmationTitle(postgres) == "Install PostgreSQL 18.6?")
        #expect(DatabaseRuntimeCopy.notInstalledDetail(postgres).contains("18.6"))
        #expect(DatabaseRuntimeCopy.addNote(postgres).contains("PostgreSQL 18.6"))
        let message = DatabaseRuntimeCopy.confirmationMessage(mysql)
        #expect(message.contains("168\u{00A0}MB") && message.contains("cdn.mysql.com"))
        #expect(message.contains("publisher signature"))
        // Redis is embedded; the on-demand engines need no compiler.
        #expect(!DatabaseRuntimeCopy.confirmationMessage(postgres).contains("Xcode"))
        #expect(DatabaseRuntimeCopy.confirmationMessage(postgres).contains("876\u{00A0}MB of free disk space"))
        #expect(DatabaseRuntimeCopy.addNote(mysql).contains("528.5\u{00A0}MB"))
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
        let postgres = try #require(SampleData.onDemandReleases.first { $0.kind == .postgresql })
        #expect(RuntimeCopy.onDemandDetail(postgres).hasPrefix("18.6, 122.5"))
    }
}
