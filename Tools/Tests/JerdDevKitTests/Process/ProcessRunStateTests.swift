import Testing

@testable import JerdDevKit

@Suite("Process run state machine")
struct ProcessRunStateTests {
    @Test("finishes when the child exits after both pipes close")
    func finishesAfterExitWhenPipesClosed() {
        var state = ProcessRunState()
        #expect(state.handle(.outputClosed(.standardOutput)).isEmpty)
        #expect(state.handle(.outputClosed(.standardError)).isEmpty)
        #expect(state.handle(.exited(status: 0)) == [.finish(.exited(status: 0))])
        #expect(state.isFinished)
    }

    @Test("waits for open pipes after exit, then finishes when they close")
    func waitsForPipesAfterExit() {
        var state = ProcessRunState()
        #expect(state.handle(.exited(status: 3)) == [.startDrainTimer])
        #expect(state.handle(.outputClosed(.standardError)).isEmpty)
        #expect(state.handle(.outputClosed(.standardOutput)) == [.finish(.exited(status: 3))])
    }

    @Test("finishes at the drain limit when a grandchild keeps a pipe open")
    func finishesAtDrainLimit() {
        var state = ProcessRunState()
        _ = state.handle(.exited(status: 0))
        #expect(state.handle(.drainLimitReached) == [.finish(.exited(status: 0))])
    }

    @Test("ignores the drain limit while the child still runs")
    func ignoresDrainLimitWhileRunning() {
        var state = ProcessRunState()
        #expect(state.handle(.drainLimitReached).isEmpty)
        #expect(!state.isFinished)
    }

    @Test("sends SIGTERM at the time limit, then SIGKILL to what is left of the group at the end")
    func terminatesAtTimeLimit() {
        var state = ProcessRunState()
        #expect(state.handle(.timeLimitReached) == [.terminate])
        _ = state.handle(.outputClosed(.standardOutput))
        _ = state.handle(.outputClosed(.standardError))
        #expect(state.handle(.exited(status: 143)) == [.kill, .finish(.timedOut(status: 143))])
    }

    @Test("kills a grandchild that keeps a pipe open after a timed-out child exits")
    func killsGroupAfterTimedOutDrain() {
        var state = ProcessRunState()
        _ = state.handle(.timeLimitReached)
        #expect(state.handle(.exited(status: 143)) == [.startDrainTimer])
        #expect(state.handle(.drainLimitReached) == [.kill, .finish(.timedOut(status: 143))])
    }

    @Test("sends SIGKILL only when the child ignores SIGTERM")
    func killsOnlyARunningChild() {
        var running = ProcessRunState()
        _ = running.handle(.timeLimitReached)
        #expect(running.handle(.killDelayReached) == [.kill])

        var exited = ProcessRunState()
        _ = exited.handle(.timeLimitReached)
        _ = exited.handle(.exited(status: 143))
        #expect(exited.handle(.killDelayReached).isEmpty)
    }

    @Test("does not terminate twice or after the exit")
    func terminatesOnce() {
        var state = ProcessRunState()
        _ = state.handle(.timeLimitReached)
        #expect(state.handle(.timeLimitReached).isEmpty)

        var exited = ProcessRunState()
        _ = exited.handle(.exited(status: 0))
        #expect(exited.handle(.timeLimitReached).isEmpty)
    }

    @Test("ignores every event after it finishes")
    func ignoresEventsAfterFinish() {
        var state = ProcessRunState()
        _ = state.handle(.outputClosed(.standardOutput))
        _ = state.handle(.outputClosed(.standardError))
        _ = state.handle(.exited(status: 0))
        #expect(state.handle(.drainLimitReached).isEmpty)
        #expect(state.handle(.timeLimitReached).isEmpty)
    }
}
