import Foundation
import JerdSystem
import os

@testable import JerdHelperCore

/// Consent that waits inside `change` until the test calls `release()`, like an open macOS approval prompt.
final class HeldConsent: ConsentRequesting, Sendable {
    private struct State {
        var asked = false
        var released = false
        var askWaiters: [CheckedContinuation<Void, Never>] = []
        var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private let inner: FakeConsent
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(_ inner: FakeConsent) { self.inner = inner }

    func waitUntilAsked() async {
        await withCheckedContinuation { continuation in
            let resume = state.withLock { current -> Bool in
                if current.asked { return true }
                current.askWaiters.append(continuation)
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

    func change(_ request: TrustConsentRequest) async throws -> Int32 {
        await withCheckedContinuation { continuation in
            let (askers, resume) = state.withLock { current -> ([CheckedContinuation<Void, Never>], Bool) in
                current.asked = true
                defer { current.askWaiters = [] }
                if !current.released { current.releaseWaiters.append(continuation) }
                return (current.askWaiters, current.released)
            }
            askers.forEach { $0.resume() }
            if resume { continuation.resume() }
        }
        return try await inner.change(request)
    }
}
