import JerdServiceKit
import Testing

@Suite struct ServiceStateTests {
    static let valid: [(ServiceState, ServiceEvent, ServiceState)] = [
        (.stopped, .startRequested, .starting),
        (.failed(reason: "x"), .startRequested, .starting),
        (.starting, .startSucceeded(pid: 7), .running(pid: 7)),
        (.starting, .startFailed(reason: "port"), .failed(reason: "port")),
        (.starting, .startFailedKeepingProcess(pid: 7, reason: "stuck"), .stuck(pid: 7, reason: "stuck")),
        (.running(pid: 7), .stopRequested(pid: 7), .stopping(pid: 7)),
        (.stuck(pid: 7, reason: "x"), .stopRequested(pid: 7), .stopping(pid: 7)),
        (.stopping(pid: 7), .stopRequested(pid: 7), .stopping(pid: 7)),
        (.stopping(pid: 7), .stopSucceeded, .stopped),
        (.stopping(pid: 7), .exitReaped(reason: "exited"), .failed(reason: "exited")),
        (.stopping(pid: 7), .stopTimedOut(pid: 7, reason: "late"), .stuck(pid: 7, reason: "late")),
        (.stopping(pid: 7), .stopRefused(reason: "inspect"), .failed(reason: "inspect")),
        (.stopped, .cleared, .stopped),
        (.failed(reason: "x"), .cleared, .stopped),
        (.stopped, .operationFailed(reason: "update"), .failed(reason: "update")),
        (.failed(reason: "x"), .operationFailed(reason: "update"), .failed(reason: "update")),
    ]

    @Test(arguments: 0..<valid.count)
    func everyListedTransitionGivesItsState(_ index: Int) {
        let (state, event, expected) = Self.valid[index]
        #expect(state.applying(event) == expected)
    }

    static let invalid: [(ServiceState, ServiceEvent)] = [
        (.starting, .startRequested),
        (.running(pid: 7), .startRequested),
        (.stuck(pid: 7, reason: "x"), .startRequested),
        (.stopping(pid: 7), .startRequested),
        (.stopped, .stopRequested(pid: 7)),
        (.starting, .stopRequested(pid: 7)),
        (.running(pid: 7), .stopSucceeded),
        (.stopped, .startSucceeded(pid: 7)),
        (.running(pid: 7), .cleared),
        (.stuck(pid: 7, reason: "x"), .cleared),
        (.running(pid: 7), .operationFailed(reason: "x")),
        (.stuck(pid: 7, reason: "x"), .exitReaped(reason: "x")),
    ]

    @Test(arguments: 0..<invalid.count)
    func anInvalidEventKeepsTheState(_ index: Int) {
        let (state, event) = Self.invalid[index]
        #expect(state.applying(event) == nil)
    }

    @Test func onlyStartingAndStoppingAreBusy() {
        #expect(ServiceState.starting.isBusy)
        #expect(ServiceState.stopping(pid: 3).isBusy)
        for state in [ServiceState.stopped, .running(pid: 3), .failed(reason: "x"), .stuck(pid: 3, reason: "x")] {
            #expect(!state.isBusy)
        }
    }

    @Test func aStuckStateKeepsItsProcessAndReason() {
        let state = ServiceState.stuck(pid: 42, reason: "did not stop")
        #expect(state.processID == 42)
        #expect(state.failure == "did not stop")
        #expect(state.title == "Failed")
        #expect(ServiceState.failed(reason: "x").processID == nil)
        #expect(ServiceState.running(pid: 9).title == "Ready")
        #expect(ServiceState.stopped.title == "Stopped")
        #expect(ServiceState.starting.title == "Starting…")
        #expect(ServiceState.stopping(pid: 1).title == "Stopping…")
    }
}
