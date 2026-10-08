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

    private struct Link: HelperLink {
        let opener: FakeUpdatedHelperOpener

        func proxy(onError: @escaping @Sendable (any Error) -> Void) -> (any JerdHelperProtocol)? {
            guard let code = opener.nextErrorCode() else { return opener.helper }
            onError(NSError(domain: NSCocoaErrorDomain, code: code))
            return nil
        }

        func invalidate() {}
    }
}
