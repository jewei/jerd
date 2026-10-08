import Foundation
import os

@testable import JerdSystem

/// The helper as launchd runs it across an app update. Until the daemon is registered again, the
/// running helper is the old one, and every call fails like XPC fails it after the update: the
/// code-signing requirement failure (NSCocoaErrorDomain 4102). After a new registration launchd
/// starts the current file, and `helper` answers.
final class FakeUpdatedHelperOpener: HelperLinkOpening, Sendable {
    struct Script: Sendable {
        /// The registrations of the daemon at which the running helper is current. Nil: never.
        var currentAfterRegistrations: Int? = 1
        /// The results of the next calls, one per proxy, before the rule above applies: an error
        /// code, or nil for an answer of `helper`.
        var nextErrorCodes: [Int?] = []
        /// The next stale calls whose 4102 arrives only at `releaseHeldFailures()`, like a reply
        /// that XPC refuses after a restart already finished.
        var heldStaleCalls = 0
        var held: [@Sendable (any Error) -> Void] = []
        var opened = 0
    }

    let helper: FakeHelper
    let daemon: FakeDaemonService
    let script: OSAllocatedUnfairLock<Script>

    init(helper: FakeHelper, daemon: FakeDaemonService, script: Script = Script()) {
        self.helper = helper
        self.daemon = daemon
        self.script = OSAllocatedUnfairLock(initialState: script)
    }

    var opened: Int { script.withLock { $0.opened } }

    func open(exporting responder: ConsentResponder, onClose: @escaping @Sendable () -> Void) throws -> any HelperLink {
        script.withLock { $0.opened += 1 }
        helper.responder.withLock { $0 = responder }
        return Link(opener: self)
    }

    /// The error code of the next call, or nil when the current helper answers.
    func nextErrorCode() -> Int? {
        let registrations = daemon.registrations
        return script.withLock { current in
            if !current.nextErrorCodes.isEmpty { return current.nextErrorCodes.removeFirst() }
            guard let needed = current.currentAfterRegistrations, registrations >= needed else {
                return HelperTransportError.signatureCode
            }
            return nil
        }
    }

    /// Delivers the held 4102 failures now.
    func releaseHeldFailures() {
        let held = script.withLock { current -> [@Sendable (any Error) -> Void] in
            defer { current.held = [] }
            return current.held
        }
        held.forEach { $0(NSError(domain: NSCocoaErrorDomain, code: HelperTransportError.signatureCode)) }
    }

    var heldCount: Int { script.withLock { $0.held.count } }

    /// Holds `onError` when a held stale call is due. Returns true when it was held.
    fileprivate func hold(_ onError: @escaping @Sendable (any Error) -> Void) -> Bool {
        script.withLock { current in
            guard current.heldStaleCalls > 0 else { return false }
            current.heldStaleCalls -= 1
            current.held.append(onError)
            return true
        }
    }

    private let silent = FakeHelper(.init(unanswered: true))

    private struct Link: HelperLink {
        let opener: FakeUpdatedHelperOpener

        func proxy(onError: @escaping @Sendable (any Error) -> Void) -> (any JerdHelperProtocol)? {
            guard let code = opener.nextErrorCode() else { return opener.helper }
            if code == HelperTransportError.signatureCode, opener.hold(onError) { return opener.silent }
            onError(NSError(domain: NSCocoaErrorDomain, code: code))
            return nil
        }

        func invalidate() {}
    }
}
