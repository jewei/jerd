import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import Testing

@testable import JerdMail

@Suite struct MailManagerTests {
    @Test func everyOperationNeedsLoadedSettings() async throws {
        let harness = try MailHarness()
        let manager = harness.manager()
        await #expect(throws: MailMessages.notLoaded) { try await manager.start() }
        await #expect(throws: MailMessages.notLoaded) { try await manager.registerRuntime(harness.runtime) }
        await #expect(throws: MailMessages.notLoaded) { try await manager.suggestedPorts() }
        #expect(await manager.snapshot().state == .stopped)
    }

    @Test func registeringARuntimeSuggestsFreePortsAndKeepsTheRuntime() async throws {
        let harness = try MailHarness()
        harness.lsof.occupy(1_025)
        let manager = harness.manager()
        #expect(try await manager.load() == MailSettings())
        #expect(mode(harness.mail.root) == 0o700)
        await #expect(throws: MailMessages.runtimeMissing) { try await manager.start() }
        try await manager.registerRuntime(harness.runtime)
        let settings = await manager.snapshot().settings
        #expect(settings.runtime == harness.runtime)
        #expect(settings.ports == MailPorts(smtp: 1_026, web: 8_025))
        try await manager.registerRuntime(harness.runtime)
        await #expect(throws: MailMessages.runtimeChanged) {
            try await manager.registerRuntime(harness.updatedRuntime())
        }
        #expect(try await harness.manager().load().runtime == harness.runtime)
    }

    @Test func aStartRunsMailpitAndAStopKeepsTheInbox() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        try await manager.start()
        guard case .running(let pid) = await manager.snapshot().state else {
            Issue.record("Expected a running inbox")
            return
        }
        #expect(exists(harness.mail.activeRunFile))
        #expect(try MarkerFile.read(MailRuntime.self, from: harness.mail.initializedMarkerFile) == harness.runtime)
        #expect(!isLockFree(harness.mail.lockFile))
        let request = try #require(await harness.processes.requests.last)
        #expect(request.arguments.contains("127.0.0.1:1025") && request.arguments.contains("127.0.0.1:8025"))
        #expect(await harness.processes.stopPolicies.isEmpty && pid > 0)
        try write("captured", to: harness.mail.inboxDatabaseFile)
        try await manager.stop()
        #expect(await manager.snapshot().state == .stopped)
        #expect(await harness.processes.stopPolicies == [.graceful(signal: SIGTERM, timeout: .seconds(30))])
        #expect(text(harness.mail.inboxDatabaseFile) == "captured")
        #expect(!exists(harness.mail.activeRunFile))
        #expect(isLockFree(harness.mail.lockFile))
    }

    @Test func aVersionInTheRuntimePathDoesNotPassAndCreatesNoInbox() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        harness.update { $0.version = "2.0.0" }
        await #expect(throws: JerdError.unavailable(MailMessages.versionMismatch)) { try await manager.start() }
        #expect(await manager.snapshot().state == .failed(reason: MailMessages.versionMismatch))
        #expect(!exists(harness.mail.inboxDirectory))
        #expect(await harness.processes.requests.isEmpty)
    }

    @Test(arguments: [true, false])
    func anOccupiedPortStartsNothingAndCreatesNoInbox(smtp: Bool) async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        harness.lsof.occupy(smtp ? 1_025 : 8_025)
        await #expect {
            try await manager.start()
        } throws: { error in
            (error as? JerdError)?.kind == .unavailable && (error as? JerdError)?.message.contains("occupied") == true
        }
        #expect(await manager.snapshot().processID == nil)
        #expect(!exists(harness.mail.inboxDirectory))
        #expect(await harness.processes.requests.isEmpty)
    }

    @Test func aPreviousLiveProcessIsNeverSignalled() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        try OwnedDirectory.create(harness.mail.root)
        let record = Data("{\"processID\":\(getpid()),\"runtimeID\":\"mailpit\"}".utf8)
        try AtomicFile.write(record, to: harness.mail.activeRunFile)
        harness.system.setSavedProcessesAlive(true)
        await #expect(throws: (any Error).self) { try await manager.start() }
        #expect(contents(harness.mail.activeRunFile) == record)
        #expect(await harness.processes.requests.isEmpty)
        #expect(await harness.processes.stopPolicies.isEmpty)
        #expect(kill(getpid(), 0) == 0)
    }

    @Test func aReadinessTimeoutShowsTheEndOfTheLog() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        harness.server.update { $0.smtpReply = "421 busy\r\n" }
        await harness.processes.setLogOutput("mailpit: database is locked\n")
        await #expect(
            throws: JerdError.timedOut("Mailpit did not pass its SMTP and web checks. mailpit: database is locked\n")
        ) { try await manager.start() }
        #expect(await manager.snapshot().processID == nil)
        #expect(!exists(harness.mail.initializedMarkerFile))
    }

    @Test func aUDPSocketFailsTheStart() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        harness.lsof.openUDP()
        await #expect(throws: JerdError.processFailed("The service opened an unexpected UDP socket.")) {
            try await manager.start()
        }
        #expect(await harness.processes.runningPIDs.isEmpty)
    }

    @Test func anUnexpectedExitIsDetectedWithoutBlockingStop() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        try await manager.start()
        await harness.processes.holdStops()
        await harness.processes.exitAll()
        guard case .stopping = await manager.snapshot().state else {
            Issue.record("Expected exit detection to stop the group in the background")
            return
        }
        let stop = Task { try await manager.stop() }
        #expect(await eventually { await harness.processes.heldStopCount == 1 })
        await harness.processes.releaseStops()
        try await stop.value
        #expect(await manager.snapshot().state == .stopped)
        #expect(await harness.processes.stopPolicies.count == 1)
    }

    @Test func anExitWithoutAStopShowsTheExitAndTheLog() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        await harness.processes.setLogOutput("panic: oops\n")
        try await manager.start()
        await harness.processes.exitAll()
        _ = await manager.snapshot()
        #expect(
            await eventually {
                await manager.snapshot().state == .failed(reason: "The mail process exited. panic: oops\n")
            })
        #expect(isLockFree(harness.mail.lockFile))
    }

    @Test func aTestEmailNeedsARunningInboxAndUsesItsSMTPPort() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        await #expect(throws: MailMessages.startBeforeTest) { try await manager.sendTestEmail() }
        try await manager.start()
        try await manager.sendTestEmail()
        let request = try #require(harness.commands.requests(named: "curl").last)
        #expect(request.arguments.contains("smtp://127.0.0.1:1025"))
        #expect(harness.uploaded?.mode == 0o600)
        try await manager.stop()
    }

    @Test func oneOperationRunsAtATime() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        await harness.processes.holdStops()
        try await manager.start()
        let stop = Task { try await manager.stop() }
        #expect(await eventually { await harness.processes.heldStopCount == 1 })
        await #expect(throws: JerdError.unavailable(MailMessages.busy)) { try await manager.sendTestEmail() }
        await #expect(throws: JerdError.unavailable(MailMessages.busy)) { try await manager.start() }
        await harness.processes.releaseStops()
        try await stop.value
    }
}
