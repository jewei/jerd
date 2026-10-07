import Foundation
import JerdServiceKit
import JerdUIFixtures
import Testing

@testable import JerdUI

/// The failure banner of a service shows one short cause, Open Log, and at most three log lines
/// with short paths, not the whole log tail of the reason.
@Suite("Service failure summary")
struct ServiceFailureSummaryTests {
    static let home = URL(fileURLWithPath: "/Users/developer")
    static let data = URL(
        fileURLWithPath: "/Users/developer/Library/Application Support/Jerd/databases/instances/A/data")

    /// A reason as `ManagedInstance` writes it: the message, a space, and the log tail.
    static let mysqlReason = """
        The database process exited. 2026-10-06T22:13:01.500Z 0 [System] [MY-010116] [Server] \
        /Users/developer/Library/Application Support/Jerd/mysql-runtimes/8.4.6/bin/mysqld (mysqld 8.4.6) starting
        2026-10-06T22:13:01.510Z 0 [Warning] [MY-010091] [Server] Can't create test file \(data.path)/host.lower-test
        2026-10-06T22:13:01.511Z 0 [Note] [MY-010747] [Server] Plugin 'FEDERATED' is disabled.

        2026-10-06T22:13:01.512Z 0 [ERROR] [MY-010273] [Server] Could not create unix socket lock file \(data.path)/mysql.sock.lock.
        2026-10-06T22:13:01.512Z 0 [ERROR] [MY-010268] [Server] Unable to setup unix socket lock file.
        2026-10-06T22:13:01.513Z 0 [ERROR] [MY-010119] [Server] Aborting
        """

    private func summary(_ reason: String, data: URL? = Self.data) -> ServiceFailureSummary {
        ServiceFailureSummary(reason: reason, dataFolder: data, homeFolder: Self.home)
    }

    @Test("A reason with a log tail shows its first sentence as the cause and the last three log lines")
    func causeAndLastLines() {
        let result = summary(Self.mysqlReason)
        #expect(result.cause == "The database process exited.")
        #expect(
            result.logLines == [
                "2026-10-06T22:13:01.512Z 0 [ERROR] [MY-010273] [Server] Could not create unix socket lock file data/mysql.sock.lock.",
                "2026-10-06T22:13:01.512Z 0 [ERROR] [MY-010268] [Server] Unable to setup unix socket lock file.",
                "2026-10-06T22:13:01.513Z 0 [ERROR] [MY-010119] [Server] Aborting",
            ])
    }

    @Test("A short message without a log stays whole, also with more than one sentence")
    func shortMessageStaysWhole() {
        let message = "RustFS exited before it was ready. Open the log for details."
        #expect(summary(message).cause == message)
        #expect(summary(message).logLines.isEmpty)
        #expect(summary("  Redis did not stop within 30 seconds.\n").cause == "Redis did not stop within 30 seconds.")
    }

    @Test("A log tail of one line still splits after the message")
    func oneLineTail() {
        let reason =
            "Mailpit exited before it was ready. " + String(repeating: "x", count: 200) + " [fatal] port in use"
        let result = summary(reason, data: nil)
        #expect(result.cause == "Mailpit exited before it was ready.")
        #expect(result.logLines.count == 1)
        #expect(result.logLines[0].hasSuffix("[fatal] port in use"))
    }

    @Test("Paths in the data folder show relative to it, other paths in the home folder with ~")
    func pathsAreShort() {
        let line = summary(Self.mysqlReason).logLines.joined()
        #expect(!line.contains("/Users/developer"))
        let first = ServiceFailureSummary.PathShortener(dataFolder: Self.data, homeFolder: Self.home)
        #expect(first.shorten("open '\(Self.data.path)/ibdata1' failed") == "open 'data/ibdata1' failed")
        #expect(first.shorten("in \(Self.data.path)") == "in data")
        #expect(
            first.shorten("\(Self.data.path)2/x") == "~/Library/Application Support/Jerd/databases/instances/A/data2/x")
        #expect(first.shorten("/Users/developer/Library/x") == "~/Library/x")
        #expect(first.shorten("/Users/developers/x") == "/Users/developers/x")
    }

    @Test("A first line without a sentence end is the cause, cut to the limit")
    func causeWithoutSentenceEnd() {
        let long = String(repeating: "a", count: 300)
        let result = summary(long + "\nsecond line", data: nil)
        #expect(result.cause.count == ServiceFailureSummary.shortReasonLimit)
        #expect(result.cause.hasSuffix("…"))
        #expect(result.logLines == ["second line"])
        #expect(summary("No sentence end\nlog line", data: nil).cause == "No sentence end")
    }

    @Test("A version number in the cause does not end the sentence")
    func decimalPointIsNotSentenceEnd() {
        let result = summary("PostgreSQL 17.6 exited before it was ready.\nFATAL: lock file", data: nil)
        #expect(result.cause == "PostgreSQL 17.6 exited before it was ready.")
        #expect(result.logLines == ["FATAL: lock file"])
    }

    @Test("The banner offers Open Log only when the log exists")
    @MainActor
    func openLogNeedsALog() {
        func banner(hasLog: Bool?) -> ServiceStateBanner {
            let files = hasLog.map {
                ServiceFiles(dataFolder: Self.data, log: Self.data, hasDataFolder: true, hasLog: $0)
            }
            return ServiceStateBanner(
                state: .failed(reason: Self.mysqlReason), subject: "MySQL", stopTitle: "Stop Service",
                identifier: "database", files: files, openLog: {})
        }
        #expect(banner(hasLog: true).openLogAction?.title == "Open Log")
        #expect(banner(hasLog: true).openLogAction?.identifier == "database.open-log")
        #expect(banner(hasLog: false).openLogAction == nil)
        #expect(banner(hasLog: nil).openLogAction == nil)
    }

    @Test("The failed fixtures carry a log tail, so the snapshots show the short banner")
    func fixturesHaveLogTails() {
        for reason in [SampleServices.reportingFailure, SampleServices.storageFailure] {
            let result = ServiceFailureSummary(reason: reason, dataFolder: nil, homeFolder: Self.home)
            #expect(result.cause.hasSuffix("exited before it was ready."))
            #expect(result.logLines.count == ServiceFailureSummary.logLineLimit)
        }
    }
}
