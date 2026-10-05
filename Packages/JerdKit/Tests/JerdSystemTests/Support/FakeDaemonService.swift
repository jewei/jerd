import Foundation
import JerdFoundation
import os

@testable import JerdSystem

/// A daemon registration with scripted states.
final class FakeDaemonService: DaemonServiceControlling, Sendable {
    let state: OSAllocatedUnfairLock<(status: HelperAvailability, afterRegister: HelperAvailability, calls: [String])>

    init(_ status: HelperAvailability, afterRegister: HelperAvailability = .enabled) {
        state = OSAllocatedUnfairLock(initialState: (status, afterRegister, []))
    }

    var status: HelperAvailability { state.withLock { $0.status } }
    var calls: [String] { state.withLock { $0.calls } }

    func register() throws {
        try state.withLock { current in
            current.calls.append("register")
            current.status = current.afterRegister
            if current.status != .enabled { throw JerdError.unavailable("Launch denied by user") }
        }
    }

    func unregister() async throws {
        state.withLock { current in
            current.calls.append("unregister")
            current.status = .notRegistered
        }
    }
}
