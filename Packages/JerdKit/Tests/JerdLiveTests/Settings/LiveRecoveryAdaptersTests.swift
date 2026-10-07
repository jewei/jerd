import Foundation
import JerdFoundation
import JerdSystem
import JerdTestSupport
import Testing

@testable import JerdLive

@Suite("Live recovery adapters")
struct LiveRecoveryAdaptersTests {
    @Test func anEmptyDataFolderHasNoRecordsAndNoBackups() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let layout = temporary.layout
        let port = LiveRecoveryPort(layout: layout)

        #expect(await port.inspectProcesses().isEmpty)
        #expect(await port.inspectBackups().isEmpty)
    }

    @Test func recoveryOfAnUnknownRecordIsRefused() async throws {
        let temporary = try TemporaryDirectory()
        defer { temporary.remove() }
        let layout = temporary.layout

        await #expect(throws: JerdError.self) { try await LiveRecoveryPort(layout: layout).recoverProcess("mail") }
        await #expect(throws: JerdError.self) { try await LiveRecoveryPort(layout: layout).removeBackup("mail/x") }
    }

    @Test func pendingRecoveryReadsTheHelperReport() async throws {
        let report = try HelperStatusMappingTests.recovery()
        let helper = RecordingHelper(
            status: HelperStatus(availability: .enabled, setup: SystemSetupStatus(recovery: report)))

        #expect(try await LiveHTTPSRecovery(helper: helper).pendingRecovery() == report)
    }

    @Test func aDisabledHelperHasNoPendingRecovery() async throws {
        #expect(try await LiveHTTPSRecovery(helper: RecordingHelper()).pendingRecovery() == nil)
    }

    @Test func aRunningHelperTransactionIsNotOfferedForRecovery() async {
        let helper = RecordingHelper(
            status: HelperStatus(availability: .enabled, setup: SystemSetupStatus(operationInProgress: "Remove")))

        await #expect(throws: HelperStatusMapping.busyError("Remove")) {
            try await LiveHTTPSRecovery(helper: helper).pendingRecovery()
        }
    }

    @Test func recoverSendsTheApprovedAction() async throws {
        let helper = RecordingHelper()
        let report = try HelperStatusMappingTests.recovery()

        try await LiveHTTPSRecovery(helper: helper).recover(report, action: .restorePrevious)

        #expect(await helper.calls == [.recover(id: report.id, action: .restorePrevious)])
    }
}
