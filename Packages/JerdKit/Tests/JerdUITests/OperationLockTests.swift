import Testing

@testable import JerdUI

@Suite("Operation lock")
@MainActor
struct OperationLockTests {
    @Test("Only one operation holds the lock; a second one does not run")
    func exclusive() async {
        let lock = OperationLock()
        let hold = Hold()
        var runs: [String] = []
        let first = lock.run("First…") {
            runs.append("first")
            while hold.isHeld { await Task.yield() }
        }
        #expect(first != nil)
        #expect(lock.work == OperationLock.Work(message: "First…", canCancel: false))
        #expect(!lock.isFree)
        #expect(lock.run("Second…") { runs.append("second") } == nil)
        hold.isHeld = false
        await first?.value
        #expect(lock.isFree)
        #expect(runs == ["first"])
    }

    @Test("Waiting work runs after the current work, in turn")
    func runWhenFreeWaits() async throws {
        let lock = OperationLock()
        let hold = Hold()
        var runs: [String] = []
        let first = lock.run("First…") {
            while hold.isHeld { await Task.yield() }
            runs.append("first")
        }
        let waiting = Task { try await lock.runWhenFree("Activating…") { runs.append("activation") } }
        for _ in 0..<20 { await Task.yield() }
        #expect(runs.isEmpty)
        hold.isHeld = false
        await first?.value
        try await waiting.value
        #expect(runs == ["first", "activation"])
        #expect(lock.isFree)
    }

    @Test("The quit closes the lock and waits for work that cannot stop")
    func shutdownWaits() async {
        let lock = OperationLock()
        let hold = Hold()
        var finished = false
        let work = lock.run("Recovering HTTPS setup…") {
            while hold.isHeld { await Task.yield() }
            finished = true
        }
        #expect(lock.shutdownMessage == "Recovering HTTPS setup…")
        let quit = Task { await lock.shutdown() }
        for _ in 0..<20 { await Task.yield() }
        #expect(!finished)
        #expect(!lock.isFree)
        hold.isHeld = false
        #expect(await quit.value)
        await work?.value
        #expect(finished)
        #expect(lock.isClosed)
        #expect(lock.run("Later…") {} == nil)
        await #expect(throws: CancellationError.self) { try await lock.runWhenFree("Activating…") {} }
        lock.resumeAfterCancelledQuit()
        #expect(lock.isFree)
    }

    @Test("The quit cancels work that can stop, with the stage message")
    func shutdownCancels() async {
        let lock = OperationLock()
        var wasCancelled = false
        lock.run("Preparing sites…", canCancel: true) {
            while !Task.isCancelled { await Task.yield() }
            wasCancelled = true
        }
        #expect(lock.shutdownMessage == ShutdownPhase.siteWork.message)
        #expect(await lock.shutdown())
        #expect(wasCancelled)
    }
}

/// Holds work open until the test releases it. A reference, so the work closure sees the change
/// without capturing a mutable local.
@MainActor private final class Hold {
    var isHeld = true
}
