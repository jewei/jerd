import Foundation
import JerdFoundation
import os

@testable import JerdSystem

/// An in-memory helper behind a fake link. It answers like the real helper and can make
/// reverse trust calls through the app's responder.
final class FakeHelper: NSObject, JerdHelperProtocol, Sendable {
    struct Script: Sendable {
        var status = SystemSetupStatus.empty
        var statusError: String?
        /// The reverse call that configure, remove, or recover makes before it replies.
        var consentRequest: TrustConsentRequest?
        var changeError: String?
        var listeners: LoopbackListenerPair?
        var transportFailure = false
        var unanswered = false
    }

    struct Received: Sendable {
        var calls: [String] = []
        var payloads: [Data] = []
        var consentStatuses: [Int32] = []
    }

    let script: OSAllocatedUnfairLock<Script>
    let received = OSAllocatedUnfairLock(initialState: Received())
    let responder = OSAllocatedUnfairLock<ConsentResponder?>(initialState: nil)

    init(_ script: Script = Script()) {
        self.script = OSAllocatedUnfairLock(initialState: script)
    }

    var calls: [String] { received.withLock { $0.calls } }

    private func record(_ call: String, _ payload: Data? = nil) -> Script {
        received.withLock { current in
            current.calls.append(call)
            if let payload { current.payloads.append(payload) }
        }
        return script.withLock { $0 }
    }

    func status(reply: @escaping @Sendable (Data?, String?) -> Void) {
        let script = record("status")
        guard !script.unanswered else { return }
        if let error = script.statusError { return reply(nil, error) }
        reply(try? HelperWireProtocol.encode(script.status), nil)
    }

    func configureSite(_ request: Data, reply: @escaping @Sendable (String?) -> Void) {
        change(record("configure", request), reply: reply)
    }

    func removeSetup(reply: @escaping @Sendable (String?) -> Void) { change(record("remove"), reply: reply) }

    func recoverSetup(_ approval: Data, reply: @escaping @Sendable (String?) -> Void) {
        change(record("recover", approval), reply: reply)
    }

    func acquireListeners(reply: @escaping @Sendable (FileHandle?, FileHandle?, String?) -> Void) {
        let script = record("acquire")
        guard !script.unanswered else { return }
        reply(
            script.listeners?.http, script.listeners?.https,
            script.listeners == nil ? "No ports (JERD-UNAVAILABLE)" : nil)
    }

    func releaseListeners(reply: @escaping @Sendable () -> Void) {
        _ = record("release")
        reply()
    }

    private func change(_ script: Script, reply: @escaping @Sendable (String?) -> Void) {
        guard let request = script.consentRequest, let responder = responder.withLock({ $0 }),
            let data = try? HelperWireProtocol.encode(request)
        else { return reply(script.changeError) }
        responder.changeTrust(data) { [received] status in
            received.withLock { $0.consentStatuses.append(status) }
            reply(
                status == 0
                    ? script.changeError : "Cannot set Jerd certificate trust: OSStatus \(status) (JERD-UNAVAILABLE)")
        }
    }
}
