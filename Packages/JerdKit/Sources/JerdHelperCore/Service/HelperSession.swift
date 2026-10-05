import Darwin
import Foundation
import JerdFoundation
import JerdSystem

/// The exported object of one XPC connection. Its owner is the connection's effective UID.
///
/// Status calls run at once. Changing calls and listener calls run in arrival order, and a call that
/// waits in the queue after the connection closed is not started. Errors cross the wire as text with
/// a stable code (`HelperWireError`).
final class HelperSession: NSObject, JerdHelperProtocol, Sendable {
    let id = UUID()
    let owner: uid_t
    private let service: HelperService
    private let consent: any ConsentRequesting
    private let lifetime = SessionLifetime()
    private let queue = SessionWorkQueue()

    init(owner: uid_t, service: HelperService, consent: any ConsentRequesting) {
        self.owner = owner
        self.service = service
        self.consent = consent
    }

    func status(reply: @escaping @Sendable (Data?, String?) -> Void) {
        let (service, owner) = (service, owner)
        Task {
            do {
                reply(try await service.status(owner: owner), nil)
            } catch {
                reply(nil, HelperWireError.text(for: error))
            }
        }
    }

    func configureSite(_ request: Data, reply: @escaping @Sendable (String?) -> Void) {
        let (service, owner, consent) = (service, owner, consent)
        change(reply) { try await service.configure(request, owner: owner, consent: consent) }
    }

    func removeSetup(reply: @escaping @Sendable (String?) -> Void) {
        let (service, owner, consent) = (service, owner, consent)
        change(reply) { try await service.remove(owner: owner, consent: consent) }
    }

    func recoverSetup(_ approval: Data, reply: @escaping @Sendable (String?) -> Void) {
        let (service, owner, consent) = (service, owner, consent)
        change(reply) { try await service.recover(approval, owner: owner, consent: consent) }
    }

    func acquireListeners(reply: @escaping @Sendable (FileHandle?, FileHandle?, String?) -> Void) {
        let (service, owner, id, lifetime) = (service, owner, id, lifetime)
        let queued = queue.enqueue {
            do {
                let pair = try await service.acquire(owner: owner, connection: id, lifetime: lifetime)
                reply(pair.http, pair.https, nil)
            } catch {
                reply(nil, nil, HelperWireError.text(for: error))
            }
        }
        if !queued { reply(nil, nil, Self.closedText) }
    }

    func releaseListeners(reply: @escaping @Sendable () -> Void) {
        let (service, id) = (service, id)
        let queued = queue.enqueue {
            await service.release(connection: id)
            reply()
        }
        if !queued { reply() }
    }

    /// Called by the connection's invalidation and interruption handlers.
    func invalidate() {
        lifetime.invalidate()
        queue.finish()
        let (service, id) = (service, id)
        Task { await service.release(connection: id) }
    }

    private func change(
        _ reply: @escaping @Sendable (String?) -> Void, _ work: @escaping @Sendable () async throws -> Void
    ) {
        let lifetime = lifetime
        let queued = queue.enqueue {
            do {
                try lifetime.check()
                try await work()
                reply(nil)
            } catch {
                reply(HelperWireError.text(for: error))
            }
        }
        if !queued { reply(Self.closedText) }
    }

    private static var closedText: String {
        HelperWireError.text(for: JerdError.unavailable("The helper connection was closed."))
    }
}
