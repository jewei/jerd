import Foundation
import JerdManifest
import JerdRuntimes
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Runtimes model")
@MainActor
struct RuntimesModelTests {
    private func model(
        _ inventory: InMemoryRuntimeInventory = InMemoryRuntimeInventory(
            inventory: SampleData.inventory, results: SampleData.checks)
    ) async -> RuntimesModel {
        let ports = InMemoryAdvancedPorts(registrations: SampleData.registrations)
        let model = RuntimesModel(port: inventory, registry: RegistrationStore(port: ports))
        await model.load()
        return model
    }

    @Test("Load reads the inventory; a failure shows once as the page banner and keeps old values")
    func loadFailure() async {
        let inventory = InMemoryRuntimeInventory(inventory: SampleData.inventory)
        let model = await model(inventory)
        await inventory.configure { $0.snapshotFailure = "The runtime records cannot be read." }
        await model.load()
        #expect(model.operation == .failed(message: "The runtime records cannot be read."))
        #expect(model.inventory == SampleData.inventory)
        model.dismissFailure()
        #expect(model.operation == .idle)
    }

    @Test("A check reads every kind, at most three at a time, and selects the default PHP branch")
    func checkAll() async {
        let inventory = InMemoryRuntimeInventory(inventory: SampleData.inventory, results: SampleData.checks)
        let model = await model(inventory)
        await model.check()?.value
        #expect(Set(await inventory.checkedKinds) == Set(RuntimeKind.allCases))
        #expect(!model.isChecking)
        #expect(model.selectedRelease(.php)?.version == "8.4.13")
        #expect(model.selectedRelease(.caddy)?.version == "2.10.2")
        #expect(model.checks[.redis]?.error != nil)
        #expect(model.selectedRelease(.redis) == nil)
    }

    @Test(
        "The selection policy keeps an offered choice, prefers the PHP branch, else the newest",
        arguments: [
            ("php-8.3.26-\(SampleData.digest)", "8.4.12", "8.3.26"),
            (nil, "8.4.12", "8.4.13"),
            (nil, "7.4.1", "8.5.0"),
            ("gone", nil, "8.5.0"),
        ] as [(String?, String?, String)])
    func selectionPolicy(current: String?, defaultPHP: String?, expected: String) throws {
        let check = try #require(SampleData.checks[.php])
        let id = RuntimeSelectionPolicy.selection(after: check, current: current, defaultPHPVersion: defaultPHP)
        #expect(check.releases.first { $0.id == id }?.version == expected)
    }

    @Test("Installation reports progress, activates, and leaves the per-kind message")
    func installSucceeds() async throws {
        let inventory = InMemoryRuntimeInventory(inventory: SampleData.inventory, results: SampleData.checks)
        let model = await model(inventory)
        await model.check()?.value
        let release = try #require(model.selectedRelease(.mailpit))
        await model.install(release)?.value
        #expect(model.installation == nil)
        #expect(model.messages[.mailpit] == "Updated to 1.28.0.")
        #expect(model.inventory.isInstalled(release))
        #expect(await inventory.activations.count == 1)
    }

    @Test(
        "Install messages follow the kind and the default choice",
        arguments: [
            (
                RuntimeKind.mysql, true,
                "Installed 8.4.7. Select it when adding a database service. Existing services keep their selected version."
            ),
            (.php, true, "PHP 8.4.7 is the default. Pinned sites keep their selected version."),
            (.php, false, "PHP 8.4.7 is available in each site’s PHP selection."),
            (.caddy, true, "Updated to 8.4.7."),
        ])
    func installMessages(kind: RuntimeKind, useAsDefault: Bool, expected: String) {
        #expect(RuntimeCopy.installedMessage(kind, version: "8.4.7", useAsDefault: useAsDefault) == expected)
    }

    @Test("Only one installation runs; a second request does nothing")
    func oneInstallation() async throws {
        let progress = RuntimeInstallProgress("Downloading…", 0.2)
        let inventory = InMemoryRuntimeInventory(
            inventory: SampleData.inventory, results: SampleData.checks, installBehavior: .suspend(progress))
        let model = await model(inventory)
        await model.check()?.value
        let mailpit = try #require(model.selectedRelease(.mailpit))
        let rustfs = try #require(model.selectedRelease(.rustfs))
        let task = model.install(mailpit)
        await waitUntil { model.installation?.progress == progress }
        #expect(model.install(rustfs) == nil)
        #expect(!model.canChangeRuntimes)
        model.cancelInstall()
        await task?.value
        #expect(model.messages[.mailpit] == "Installation cancelled.")
        #expect(await inventory.installed.map(\.kind) == [.mailpit])
    }

    @Test("A failed installation shows its message in the section of its kind")
    func installFails() async throws {
        let inventory = InMemoryRuntimeInventory(
            inventory: SampleData.inventory, results: SampleData.checks, installBehavior: .fail("The download failed."))
        let model = await model(inventory)
        await model.check()?.value
        await model.install(try #require(model.selectedRelease(.rustfs)))?.value
        #expect(model.errors[.rustfs] == "The download failed.")
        #expect(model.messages[.rustfs] == nil)
    }

    @Test("Quit cancels a download, waits for it, and blocks new work until resumed")
    func shutdownCancels() async throws {
        let inventory = InMemoryRuntimeInventory(
            inventory: SampleData.inventory, results: SampleData.checks,
            installBehavior: .suspend(RuntimeInstallProgress("Downloading…")))
        let model = await model(inventory)
        await model.check()?.value
        model.install(try #require(model.selectedRelease(.mailpit)))
        await waitUntil { model.installation?.progress != nil }
        #expect(await model.shutdown())
        #expect(model.installation == nil)
        #expect(model.check() == nil)
        model.resumeAfterCancelledQuit()
        #expect(model.canCheck)
    }

    @Test("Use as Default changes the default PHP; a failure shows on the page")
    func useAsDefault() async throws {
        let ports = InMemoryAdvancedPorts(registrations: SampleData.registrations)
        let model = RuntimesModel(
            port: InMemoryRuntimeInventory(inventory: SampleData.inventory), registry: RegistrationStore(port: ports))
        await model.load()
        #expect(model.registeredPHP.map(\.version) == ["8.4.12", "8.3.24"])
        #expect(model.registeredPHP.first?.buildDigest == SampleData.digest)
        let php83 = try #require(model.registeredPHP.last)
        await model.useAsDefault(php83)?.value
        #expect(model.defaultPHPID == php83.id)
        #expect(model.useAsDefault(php83) == nil)
        await ports.configure { $0.failure = "Load valid site settings before changing PHP or Caddy." }
        await model.useAsDefault(try #require(model.registeredPHP.first))?.value
        #expect(model.operation == .failed(message: "Load valid site settings before changing PHP or Caddy."))
    }

    @Test("Installed versions sort newest first without duplicates")
    func versionSort() {
        let snapshot = RuntimeInventorySnapshot(versions: [.php: ["8.3.24", "8.10.1", "8.4.12", "8.4.12", "custom"]])
        #expect(snapshot.installedVersions(.php) == ["8.10.1", "8.4.12", "8.3.24", "custom"])
        #expect(snapshot.installedVersions(.redis).isEmpty)
    }

    @Test("Footers name the check date, then the note of the kind")
    func footers() {
        #expect(RuntimeCopy.footer(.caddy, checkedAt: nil) == nil)
        #expect(RuntimeCopy.footer(.redis, checkedAt: nil) == "Redis builds need the Xcode command line tools.")
        #expect(RuntimeCopy.footer(.caddy, checkedAt: "Oct 6, 2026 at 9:41 AM") == "Checked Oct 6, 2026 at 9:41 AM.")
        #expect(
            RuntimeCopy.footer(.mysql, checkedAt: "Oct 6, 2026 at 9:41 AM")
                == "Checked Oct 6, 2026 at 9:41 AM. MySQL uses the 8.4 LTS series.")
        #expect(RuntimeCopy.installTitle(.redis, hasInstalledVersion: true) == "Install Version")
        #expect(RuntimeCopy.installTitle(.mysql, hasInstalledVersion: false) == "Install")
        #expect(RuntimeCopy.installTitle(.caddy, hasInstalledVersion: false) == "Install")
        #expect(RuntimeCopy.installTitle(.caddy, hasInstalledVersion: true) == "Update")
    }

    @Test("The Release row says how each release is verified")
    func verificationText() {
        #expect(RuntimeCopy.verificationDetail(SampleData.release(.caddy, "2.10.2")) == "Package build 3f7c2a9b41d8")
        #expect(
            RuntimeCopy.verificationDetail(SampleData.release(.mysql, "8.4.7", digest: nil, signed: true)).hasPrefix(
                "Install checks the publisher signature"))
        #expect(
            RuntimeCopy.verificationDetail(SampleData.release(.laravel, "5.19.0", digest: nil)).hasPrefix(
                "Composer verifies"))
    }
}
