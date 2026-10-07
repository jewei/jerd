import JerdDatabases
import JerdDesign
import JerdServiceKit
import JerdStorage
import JerdUIFixtures
import Testing

@testable import JerdUI

@Suite("Service input rules")
struct ServiceRulesTests {
    @Test(
        "A port is a whole number from 1024 to 65535",
        arguments: [
            ("1024", UInt16(1024)), ("65535", 65535), (" 3306 ", 3306), ("1023", nil), ("65536", nil), ("", nil),
            ("80a", nil), ("-1", nil), ("٣٣٠٦", nil),
        ] as [(String, UInt16?)])
    func portRule(text: String, port: UInt16?) {
        #expect(PortInput.parse(text) == port)
    }

    @Test("Two ports must both be valid and differ")
    func portPair() {
        #expect(PortsDraft(first: "1025", second: "8025").ports! == (1025, 8025))
        #expect(PortsDraft(first: "1025", second: "1025").issue == "Enter two different ports from 1024 to 65535.")
        #expect(PortsDraft(first: "80", second: "8025").ports == nil)
    }

    @Test("Each service state has one label and tone; stuck asks for attention")
    func stateDisplay() {
        #expect(ServiceState.stopped.displayStatus == DisplayStatus("Stopped", tone: .idle))
        #expect(ServiceState.starting.displayStatus == DisplayStatus("Starting…", tone: .busy))
        #expect(ServiceState.running(pid: 1).displayStatus == DisplayStatus("Ready", tone: .ready))
        #expect(ServiceState.stopping(pid: 1).displayStatus == DisplayStatus("Stopping…", tone: .busy))
        #expect(ServiceState.failed(reason: "x").displayStatus == DisplayStatus("Failed", tone: .failed))
        #expect(
            ServiceState.stuck(pid: 1, reason: "x").displayStatus == DisplayStatus("Did not stop", tone: .attention))
    }

    @Test("Stop is the action while Jerd owns a process, also to retry a stuck stop")
    func offersStop() {
        #expect(ServiceState.running(pid: 1).offersStop)
        #expect(ServiceState.stuck(pid: 1, reason: "x").offersStop)
        #expect(!ServiceState.failed(reason: "x").offersStop)
        #expect(!ServiceState.stopped.offersStop)
    }

    @Test("The stuck message names the process, the kept lock, the retry, and that Quit can be cancelled")
    func stuckMessage() {
        let text = ServiceStateBanner.stuckMessage(reason: "Timed out.", pid: 42, stopTitle: "Stop Mail")
        #expect(
            text
                == "Timed out. Jerd keeps process 42, its run record, and its data lock, so nothing else can change "
                + "the data. Select Stop Mail to try again. Quit also tries to stop it; if it still does not stop, "
                + "Jerd stays open.")
        #expect(!text.contains("Quit waits"))
    }

    @Test("A bucket status follows the storage state while storage is not running")
    func bucketStatus() {
        let bucket = StorageBucket(name: "uploads", setupComplete: true)
        let failed = BucketStatus(bucket: bucket, state: .stuck(pid: 1, reason: "x"), listed: [])
        #expect(failed.displayStatus == DisplayStatus("Storage failed", tone: .attention))
        let missing = BucketStatus(bucket: bucket, state: .running(pid: 1), listed: [])
        #expect(missing.displayStatus == DisplayStatus("Bucket missing", tone: .attention))
    }
}
