import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import Testing

@testable import JerdDatabases

/// Review final-domain-r1 M1: a database server that survived a crash is not shown as Stopped, and
/// its Start names process recovery, not the occupied port.
@Suite struct DatabaseRecoveryStateTests {
    @Test func aSurvivingServerOfAnEarlierRunIsShownAndNamedByStart() async throws {
        let harness = try DatabaseHarness()
        let manager = try await harness.loadedManager()
        let service = try await manager.add(name: "Cache", runtimeID: harness.runtime(.redis).id, port: 26_390)
        let location = harness.layout.instance(service.id).record
        try OwnedDirectory.create(location.folder, within: harness.layout.root)
        let record = ActiveRunRecord(
            processID: getpid(), runtimeID: harness.runtime(.redis).id, identity: nil, controller: nil,
            gracefulSignal: SIGINT)
        try ActiveRunRecordFile.write(record, to: location.recordFile)
        harness.system.setSavedProcessesAlive(true)
        harness.lsof.occupy(26_390)
        let expected = ExpectedErrors.liveRecordOfThisProcess
        #expect(await manager.snapshot().state(of: service.id) == .failed(reason: expected.message))
        await #expect(throws: expected) { try await manager.start(service.id) }
        #expect(await harness.processes.requests.isEmpty)
        #expect(try ActiveRunRecordFile.read(location.recordFile) == record)
    }
}
