import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdMail

@Suite struct MailEditTests {
    static let ports = MailPorts(smtp: 2_525, web: 8_026)

    @Test func aStoppedInboxMovesToFreePortsAndStartsThere() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        try await manager.edit(ports: Self.ports)
        #expect(await manager.snapshot().settings.ports == Self.ports)
        #expect(try MailSettingsStore(layout: harness.mail).load().ports == Self.ports)
        try await manager.start()
        let request = try #require(await harness.processes.requests.last)
        #expect(request.arguments.contains("127.0.0.1:2525") && request.arguments.contains("127.0.0.1:8026"))
        try await manager.stop()
    }

    @Test func aRunningInboxKeepsItsPorts() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        try await manager.start()
        await #expect(throws: MailMessages.stopBeforeEditing) { try await manager.edit(ports: Self.ports) }
        #expect(await manager.snapshot().settings.ports == MailSettings.defaultPorts)
        try await manager.stop()
    }

    @Test func invalidOrOccupiedPortsAreRefused() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        await #expect(throws: MailMessages.settingsInvalid) {
            try await manager.edit(ports: MailPorts(smtp: 2_525, web: 2_525))
        }
        harness.lsof.occupy(8_026)
        await #expect(throws: JerdError.unavailable("Local port 8026 is occupied. No process was stopped.")) {
            try await manager.edit(ports: Self.ports)
        }
        #expect(await manager.snapshot().settings.ports == MailSettings.defaultPorts)
    }

    @Test func theRunRecordIsCheckedWithTheInboxLockHeld() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        let record = Data("{\"processID\":\(getpid()),\"runtimeID\":\"mailpit\"}".utf8)
        try AtomicFile.write(record, to: harness.mail.activeRunFile)
        harness.system.setSavedProcessesAlive(true)
        await #expect(throws: (any Error).self) { try await manager.edit(ports: Self.ports) }
        #expect(contents(harness.mail.activeRunFile) == record)
        harness.system.setSavedProcessesAlive(false)
        let other = try InstanceLock.acquire(at: harness.mail.lockFile, messages: MailMessages.instance.lock)
        await #expect(throws: JerdError.locked("Another Jerd process is using this mail inbox.")) {
            try await manager.edit(ports: Self.ports)
        }
        #expect(contents(harness.mail.activeRunFile) == record)
        other.release()
        try await manager.edit(ports: Self.ports)
        #expect(!exists(harness.mail.activeRunFile))
        #expect(isLockFree(harness.mail.lockFile))
    }

    @Test func aSuccessfulEditClearsAnEarlierFailure() async throws {
        let harness = try MailHarness()
        let manager = try await harness.loadedManager()
        harness.lsof.occupy(1_025)
        await #expect(throws: (any Error).self) { try await manager.start() }
        guard case .failed = await manager.snapshot().state else {
            Issue.record("Expected a failed start")
            return
        }
        try await manager.edit(ports: Self.ports)
        #expect(await manager.snapshot().state == .stopped)
    }
}
