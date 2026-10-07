import Darwin
import Dispatch
import Foundation
import os

/// Handles SIGINT, SIGTERM, and SIGHUP for `./dev`. Children run in their own process groups, so a
/// Ctrl-C in the terminal or a stop from CI reaches only `./dev`. The forwarder sends the signal to
/// every child group, waits a short time, sends SIGKILL to any group that remains, and then ends
/// `./dev` with 128 plus the signal number.
struct SignalForwarder: Sendable {
    static let forwardedSignals: [Int32] = [SIGINT, SIGTERM, SIGHUP]

    let groups: ChildProcessGroups
    /// How long the children have to stop after the forwarded signal.
    let gracePeriod: Duration

    /// Forwards the signal and returns the exit status for `./dev`. It blocks until the groups are
    /// gone or the grace period ends, so call it only from the signal queue.
    func interrupt(by signal: Int32) -> Int32 {
        groups.signalAll(signal, stopStarting: true)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: gracePeriod)
        while !groups.running.isEmpty, clock.now < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        groups.signalAll(SIGKILL)
        return 128 + signal
    }

    private static let sources = OSAllocatedUnfairLock(initialState: [any DispatchSourceSignal]())
    private static let interruptNote = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// Text that a stop by signal prints before `./dev` ends, for example what a release made public.
    static func setInterruptNote(_ text: String?) {
        interruptNote.withLock { $0 = text }
    }

    /// Installs the handlers for the live tool. Call it once, before the first child starts.
    static func installLive(output: any TextOutput) {
        let forwarder = SignalForwarder(groups: .shared, gracePeriod: .seconds(5))
        let queue = DispatchQueue(label: "jerd-dev.signals")
        let installed = forwardedSignals.map { number -> any DispatchSourceSignal in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler {
                output.write("error: Stopped by signal \(number). Stopping the running commands.\n", to: .standardError)
                let status = forwarder.interrupt(by: number)
                if let note = interruptNote.withLock({ $0 }) {
                    output.write(Console.indented(note), to: .standardError)
                }
                exit(status)
            }
            source.resume()
            return source
        }
        sources.withLock { $0 += installed }
    }
}
