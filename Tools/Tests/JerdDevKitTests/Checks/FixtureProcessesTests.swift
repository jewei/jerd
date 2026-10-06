import Foundation
import Testing

@testable import JerdDevKit

@Suite("Test app processes")
struct FixtureProcessesTests {
    static let executable = URL(filePath: "/work/case/installed/Updater Test.app/Contents/MacOS/UpdaterTest")

    @Test("Reads each recorded PID once and ignores other lines")
    func recordedPIDs() {
        let events = "pid:101\nlaunched:1\npid:x\npid:-4\npid:202\npid:101\n"
        #expect(FixtureProcesses.recordedPIDs(in: events) == [101, 202])
    }

    @Test("A PID counts only while its executable is this case's test app")
    func ownership() {
        let inspector = FakeProcessInspector()
        inspector.add(101, path: Self.executable.path)
        inspector.add(202, path: "/usr/bin/unrelated")
        let processes = FixtureProcesses(executable: Self.executable, inspector: inspector)
        #expect(processes.owned(events: "pid:101\npid:202\npid:303\n") == [101])
    }

    @Test("Stops only owned processes and waits until they end")
    func stopsOwned() async throws {
        let inspector = FakeProcessInspector()
        inspector.add(101, path: Self.executable.path)
        inspector.add(202, path: "/usr/bin/unrelated")
        let processes = FixtureProcesses(executable: Self.executable, inspector: inspector)
        try await processes.stopOwned(events: "pid:101\npid:202\n", clock: FakeHarnessClock())
        #expect(inspector.terminatedPIDs == [101])
    }

    @Test("Fails after the limit when an owned process keeps running")
    func failsWhenAProcessStays() async {
        let inspector = FakeProcessInspector()
        inspector.add(101, path: Self.executable.path, ignoresTerminate: true)
        let processes = FixtureProcesses(executable: Self.executable, inspector: inspector)
        let clock = FakeHarnessClock()
        await #expect(throws: DevFailure.self) { try await processes.stopOwned(events: "pid:101\n", clock: clock) }
        #expect(clock.now().timeIntervalSince(FakeHarnessClock.start) >= 5)
    }

    @Test("The live inspector finds this process and no process for an unused PID")
    func liveInspector() {
        let inspector = LiveProcessInspector()
        let path = inspector.executablePath(of: ProcessInfo.processInfo.processIdentifier)
        #expect(path.map { URL(filePath: $0).lastPathComponent }?.isEmpty == false)
        #expect(inspector.executablePath(of: 0) == nil)
        #expect(!inspector.terminate(0))
    }
}
