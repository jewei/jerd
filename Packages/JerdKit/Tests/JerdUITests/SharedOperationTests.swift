import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Shared operation lock in the app")
@MainActor
struct SharedOperationTests {
    @Test("Advanced work excludes Runtimes and command-line tools work, and the quit waits for it")
    func advancedWorkIsExclusive() async {
        let ports = InMemoryAdvancedPorts(findings: SampleData.findings, registrations: SampleData.registrations)
        let fixture = AppFixture(advanced: ports)
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        await fixture.state.commandLineTools.load()
        await fixture.state.advanced.inspect()?.value
        await ports.configure { $0.isHeld = true }
        fixture.state.advanced.confirmation = .forFinding(SampleData.findings[0])
        let recovery = fixture.state.advanced.confirm()
        #expect(recovery != nil)
        #expect(!fixture.state.runtimes.canChangeRuntimes)
        #expect(fixture.state.runtimes.useAsDefault(SampleData.inventory.php[1]) == nil)
        #expect(!fixture.state.commandLineTools.canInstall)

        var replies: [Bool] = []
        _ = fixture.state.requestTermination { replies.append($0) }
        await waitUntil {
            fixture.state.shutdown.message == AdvancedConfirmation.recoverProcess(SampleData.findings[0]).workingMessage
        }
        for _ in 0..<50 { await Task.yield() }
        #expect(replies.isEmpty)
        #expect(fixture.features.allSatisfy { $0.shutdownCount == 0 })
        #expect(!fixture.state.advanced.isIdle)
        await ports.configure { $0.isHeld = false }
        await waitUntil { !replies.isEmpty }
        await recovery?.value
        #expect(replies == [true])
        #expect(await ports.calls == ["recover Mail"])
    }

    @Test("The quit waits for a default PHP change before PHP-FPM stops")
    func quitWaitsForDefaultChange() async {
        let inventory = InMemoryRuntimeInventory(inventory: SampleData.inventory)
        let fixture = AppFixture(runtimes: inventory)
        defer { fixture.removeDefaults() }
        await fixture.state.launch()
        await inventory.configure { $0.holdsDefaultChange = true }
        let change = fixture.state.runtimes.useAsDefault(SampleData.inventory.php[1])
        #expect(change != nil)
        #expect(!fixture.state.advanced.isIdle)
        var replies: [Bool] = []
        _ = fixture.state.requestTermination { replies.append($0) }
        await waitUntil { fixture.state.shutdown.message == "Changing the default PHP…" }
        for _ in 0..<50 { await Task.yield() }
        #expect(replies.isEmpty)
        #expect(fixture.features.allSatisfy { $0.shutdownCount == 0 })
        await inventory.configure { $0.holdsDefaultChange = false }
        await waitUntil { !replies.isEmpty }
        #expect(replies == [true])
        #expect(await inventory.defaultRequests == [SampleData.inventory.php[1].id])
    }

    @Test("During a quit, Advanced, Runtimes, and command-line tools actions are off")
    func quitDisablesSettingsWork() async {
        let fixture = AppFixture()
        defer { fixture.removeDefaults() }
        await fixture.services.storage.configure { $0.stopBehavior = .suspend }
        await fixture.state.launch()
        await fixture.state.commandLineTools.load()
        _ = fixture.state.requestTermination { _ in }
        await waitUntil { fixture.state.shutdown.message == ShutdownPhase.storage.message }
        #expect(!fixture.state.advanced.isIdle)
        #expect(fixture.state.advanced.inspect() == nil)
        #expect(!fixture.state.runtimes.canChangeRuntimes)
        #expect(!fixture.state.commandLineTools.canInstall)
    }
}
