import Foundation
import JerdFoundation
import os

/// The app-side gate of reverse trust calls. Each operation opens its own scope and gets a token;
/// only that token can close it, and a second operation cannot open a scope while one is open.
///
/// This fixes the shared scope slot (problem 8): an operation can no longer replace or clear
/// the scope of another operation.
public final class ConsentGate: Sendable {
    private struct Open: Sendable {
        let token: ConsentToken
        let scope: ConsentScope
    }

    private let state = OSAllocatedUnfairLock<Open?>(initialState: nil)

    public init() {}

    /// Opens `scope` for one operation.
    /// - Throws: `.unavailable` while another operation holds a scope.
    public func open(_ scope: ConsentScope) throws -> ConsentToken {
        let token = ConsentToken()
        let opened = state.withLock { current -> Bool in
            guard current == nil else { return false }
            current = Open(token: token, scope: scope)
            return true
        }
        guard opened else { throw JerdError.unavailable("Wait for the current system operation to finish.") }
        return token
    }

    /// Closes the scope of `token`. A stale token changes nothing.
    public func close(_ token: ConsentToken) {
        state.withLock { current in
            if current?.token == token { current = nil }
        }
    }

    /// True when the open scope allows `request`. Without an open scope, nothing is allowed.
    public func allows(_ request: TrustConsentRequest) -> Bool {
        state.withLock { $0?.scope.allows(request) == true }
    }
}
