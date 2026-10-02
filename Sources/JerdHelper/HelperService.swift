import Foundation
import JerdCore

final class SessionLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    func invalidate() { lock.withLock { valid = false } }
    func check() throws {
        guard lock.withLock({ valid }) else { throw JerdError.unavailable("The helper connection was closed.") }
    }
}

actor HelperService {
    private let store = PrivilegedSetupStore(
        directory: URL(fileURLWithPath: "/Library/Application Support/JerdHelper"), expectedFileOwner: 0,
        hosts: AtomicHostsFile(url: URL(fileURLWithPath: "/private/etc/hosts"), expectedOwner: 0),
        certificates: SystemCertificateTrust())
    private var lease: (connection: UUID, owner: uid_t, sockets: ListeningSockets)?
    private var busy = false

    func status(owner: uid_t) async throws -> Data {
        try JSONEncoder().encode(await store.status(ownerUID: owner))
    }

    func configure(_ data: Data, owner: uid_t, consent: TrustConsentClient) async throws {
        guard data.count < 131_072, !busy, lease == nil else { throw JerdError.invalid("Stop Jerd's environment before changing system setup.") }
        busy = true
        defer { busy = false }
        let request = try JSONDecoder().decode(SystemRegistrationRequest.self, from: data)
        let reservation = try ListeningSockets.bind(httpPort: 80, httpsPort: 443)
        defer { reservation.close() }
        try await store.configure(request, ownerUID: owner, trustManager: SystemCertificateTrust(consent: consent))
    }

    func acquire(owner: uid_t, connection: UUID, lifetime: SessionLifetime) async throws -> ListeningSockets {
        try lifetime.check()
        guard !busy else { throw JerdError.unavailable("System setup is in progress. Retry shortly.") }
        if let lease {
            guard lease.connection == connection, lease.owner == owner else { throw JerdError.unavailable("Another Jerd connection owns the standard ports.") }
            return lease.sockets
        }
        busy = true
        defer { busy = false }
        let status = try await store.status(ownerUID: owner)
        try lifetime.check()
        guard status.hostsConfigured, status.trustConfigured else { throw JerdError.unavailable("Approved host and certificate setup is required.") }
        let sockets = try ListeningSockets.bind(httpPort: 80, httpsPort: 443)
        lease = (connection, owner, sockets)
        return sockets
    }

    func release(connection: UUID) {
        if lease?.connection == connection { lease?.sockets.close(); lease = nil }
    }

    func remove(owner: uid_t, consent: TrustConsentClient) async throws {
        guard !busy, lease == nil else { throw JerdError.invalid("Stop Jerd's environment before removing system setup.") }
        busy = true
        defer { busy = false }
        try await store.remove(ownerUID: owner, trustManager: SystemCertificateTrust(consent: consent))
    }

    func recover(_ data: Data, owner: uid_t, consent: TrustConsentClient) async throws {
        guard data.count < 4096, !busy, lease == nil else { throw JerdError.invalid("Stop Jerd's environment before recovering system setup.") }
        busy = true; defer { busy = false }
        let approval = try JSONDecoder().decode(SystemRecoveryApproval.self, from: data)
        let reservation = approval.action == .restorePrevious ? try ListeningSockets.bind(httpPort: 80, httpsPort: 443) : nil
        defer { reservation?.close() }
        try await store.recover(approval, ownerUID: owner, trustManager: SystemCertificateTrust(consent: consent))
    }
}

final class HelperSession: NSObject, JerdHelperProtocol, @unchecked Sendable {
    let id = UUID()
    private let owner: uid_t
    private let service: HelperService
    private let lifetime = SessionLifetime()
    private let consent: TrustConsentClient
    init(owner: uid_t, service: HelperService, consent: TrustConsentClient) {
        self.owner = owner; self.service = service; self.consent = consent
    }

    func status(reply: @escaping @Sendable (Data?, String?) -> Void) {
        Task {
            do { reply(try await service.status(owner: owner), nil) }
            catch { reply(nil, error.localizedDescription) }
        }
    }
    func configureSite(_ request: Data, reply: @escaping @Sendable (String?) -> Void) {
        Task {
            do { try await service.configure(request, owner: owner, consent: consent); reply(nil) }
            catch { reply(error.localizedDescription) }
        }
    }
    func acquireListeners(reply: @escaping @Sendable (FileHandle?, FileHandle?, String?) -> Void) {
        Task {
            do { let sockets = try await service.acquire(owner: owner, connection: id, lifetime: lifetime); reply(sockets.http, sockets.https, nil) }
            catch { reply(nil, nil, error.localizedDescription) }
        }
    }
    func releaseListeners(reply: @escaping @Sendable () -> Void) {
        Task { await service.release(connection: id); reply() }
    }
    func removeSetup(reply: @escaping @Sendable (String?) -> Void) {
        Task {
            do { try await service.remove(owner: owner, consent: consent); reply(nil) }
            catch { reply(error.localizedDescription) }
        }
    }
    func recoverSetup(_ approval: Data, reply: @escaping @Sendable (String?) -> Void) {
        Task {
            do { try await service.recover(approval, owner: owner, consent: consent); reply(nil) }
            catch { reply(error.localizedDescription) }
        }
    }
    func invalidate() { lifetime.invalidate(); Task { await service.release(connection: id) } }
}

final class HelperListener: NSObject, NSXPCListenerDelegate {
    private let service = HelperService()
    private let requirement: String
    init(requirement: String) { self.requirement = requirement }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier >= 501 else { return false }
        // The listener checks the requirement before this callback. Apply it to
        // every later message too, so exec/re-sign races cannot change the peer.
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: JerdTrustConsentProtocol.self)
        let session = HelperSession(owner: connection.effectiveUserIdentifier, service: service,
                                    consent: TrustConsentClient(connection: connection))
        connection.exportedInterface = NSXPCInterface(with: JerdHelperProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { session.invalidate() }
        connection.interruptionHandler = { session.invalidate() }
        connection.resume()
        return true
    }
}
