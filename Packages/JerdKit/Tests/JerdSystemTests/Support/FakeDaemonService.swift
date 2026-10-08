import Foundation
import JerdFoundation
import os

@testable import JerdSystem

/// A daemon registration with scripted states, and the process table of its helper.
///
/// It models the race of the field: after `unregister()` the old helper process still runs for
/// `exitingChecks` process checks, and with `refusesWhileExiting` a `register()` in that time fails
/// with POSIX EPERM ("Operation not permitted") and leaves the daemon not registered.
final class FakeDaemonService: DaemonServiceControlling, HelperProcessInspecting, Sendable {
    struct State: Sendable {
        var status: HelperAvailability
        var afterRegister: HelperAvailability
        var calls: [String] = []
        /// The process checks that still see the old helper after `unregister()`.
        var exitingChecks = 0
        var oldHelperRuns = false
        var refusesWhileExiting = false
        /// Errors that the next `register()` calls throw, in order, before the scripted result.
        var registerErrors: [NSError] = []
        /// The error of the next `unregister()`.
        var unregisterError: NSError?
        /// When set, `unregister()` waits here before it changes anything, like a slow launchd.
        var unregisterPause: PauseGate?
        /// The number of successful registrations: each one makes launchd start the current file.
        var registrations = 0
        var processChecks = 0
    }

    let state: OSAllocatedUnfairLock<State>

    init(_ status: HelperAvailability, afterRegister: HelperAvailability = .enabled) {
        state = OSAllocatedUnfairLock(initialState: State(status: status, afterRegister: afterRegister))
    }

    var status: HelperAvailability { state.withLock { $0.status } }
    var calls: [String] { state.withLock { $0.calls } }
    var registrations: Int { state.withLock { $0.registrations } }

    static let operationNotPermitted = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))

    func configure(_ change: @Sendable (inout State) -> Void) { state.withLock { change(&$0) } }

    func register() throws {
        try state.withLock { current in
            current.calls.append("register")
            if !current.registerErrors.isEmpty { throw current.registerErrors.removeFirst() }
            if current.refusesWhileExiting, current.oldHelperRuns { throw Self.operationNotPermitted }
            current.status = current.afterRegister
            if current.status != .enabled { throw JerdError.unavailable("Launch denied by user") }
            current.registrations += 1
        }
    }

    func unregister() async throws {
        if let pause = state.withLock({ $0.unregisterPause }) { await pause.pause(.zero) }
        try state.withLock { current in
            current.calls.append("unregister")
            if let error = current.unregisterError { throw error }
            current.status = .notRegistered
            current.oldHelperRuns = current.exitingChecks > 0
        }
    }

    func isHelperRunning() -> Bool {
        state.withLock { current in
            current.processChecks += 1
            guard current.oldHelperRuns else { return false }
            current.exitingChecks -= 1
            current.oldHelperRuns = current.exitingChecks > 0
            return true
        }
    }

    /// The registration on this fake, with no signing check and pauses that only count.
    func registration(pauses: OSAllocatedUnfairLock<[Duration]> = .init(initialState: [])) -> HelperRegistration {
        HelperRegistration(
            service: self, processes: self, requireSignedBuild: {},
            pause: { duration in pauses.withLock { $0.append(duration) } })
    }
}
