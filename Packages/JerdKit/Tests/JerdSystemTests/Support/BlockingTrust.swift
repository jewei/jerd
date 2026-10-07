import Foundation
import os

@testable import JerdSystem

/// Trust changes that wait inside `install` until the test calls `release()`, like a macOS approval prompt.
final class BlockingTrust: CertificateTrustChanging, Sendable {
    private struct State {
        var started = false
        var released = false
        var startWaiters: [CheckedContinuation<Void, Never>] = []
        var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private let inner: FakeTrust
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(_ inner: FakeTrust) { self.inner = inner }

    func waitUntilInstallStarts() async {
        await withCheckedContinuation { continuation in
            let resume = state.withLock { current -> Bool in
                if current.started { return true }
                current.startWaiters.append(continuation)
                return false
            }
            if resume { continuation.resume() }
        }
    }

    func release() {
        let waiters = state.withLock { current -> [CheckedContinuation<Void, Never>] in
            current.released = true
            defer { current.releaseWaiters = [] }
            return current.releaseWaiters
        }
        waiters.forEach { $0.resume() }
    }

    func install(_ trust: CertificateTrust, replacingOwned: Bool) async throws {
        await withCheckedContinuation { continuation in
            let (starters, resume) = state.withLock { current -> ([CheckedContinuation<Void, Never>], Bool) in
                current.started = true
                defer { current.startWaiters = [] }
                if !current.released { current.releaseWaiters.append(continuation) }
                return (current.startWaiters, current.released)
            }
            starters.forEach { $0.resume() }
            if resume { continuation.resume() }
        }
        try await inner.install(trust, replacingOwned: replacingOwned)
    }

    func remove(_ certificate: InstallationCertificate) async throws {
        try await inner.remove(certificate)
    }
}
