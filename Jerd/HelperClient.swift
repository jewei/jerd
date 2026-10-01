import Foundation
import ServiceManagement
import JerdCore

/// The only client of the privileged interface. XPC verifies both code identities.
actor HelperClient: SystemIntegrating {
    private var connection: NSXPCConnection?
    private var connectionID: UUID?
    private let consent = TrustConsentService()

    func registerAfterApproval() throws {
        _ = try SystemService.currentTeamID()
        let service = SMAppService.daemon(plistName: SystemService.plistName)
        // A new daemon can report notFound before its first BTM registration.
        if service.status == .notRegistered || service.status == .notFound {
            do { try service.register() }
            catch {
                // register() can throw LaunchDeniedByUser while registration is
                // retained and waiting for approval in System Settings.
                guard service.status == .requiresApproval || service.status == .enabled else { throw error }
            }
        }
        switch service.status {
        case .enabled: return
        case .requiresApproval:
            throw JerdError.unavailable("Allow Jerd in System Settings → General → Login Items & Extensions, then select Enable HTTPS again.")
        default:
            throw JerdError.unavailable("The Jerd helper is not enabled. Use a signed app in a stable location and check Login Items & Extensions.")
        }
    }

    func isEnabled() -> Bool { SMAppService.daemon(plistName: SystemService.plistName).status == .enabled }

    func status() async throws -> SystemSetupStatus {
        let data: Data = try await call { proxy, reply in
            proxy.status { data, error in
                if let data { reply.resolve(.success(data)) }
                else { reply.resolve(.failure(JerdError.unavailable(error ?? "No helper status was returned."))) }
            }
        }
        return try JSONDecoder().decode(SystemSetupStatus.self, from: data)
    }

    func configure(_ request: SystemRegistrationRequest) async throws {
        let previous = try await status()
        var hosts = Set(request.hostnames)
        if previous.certificateDER == request.certificateDER { hosts.formUnion(previous.hostnames) }
        try consent.authorize(installationID: request.installationID, certificateDER: request.certificateDER, hostnames: hosts)
        defer { consent.clear() }
        let data = try JSONEncoder().encode(request)
        let _: Bool = try await call(timeout: nil) { proxy, reply in
            proxy.configureSite(data) { error in
                if let error { reply.resolve(.failure(JerdError.unavailable(error))) }
                else { reply.resolve(.success(true)) }
            }
        }
    }

    func acquireListeners() async throws -> ListeningSockets {
        try await call { proxy, reply in
            proxy.acquireListeners { http, https, error in
                if let http, let https { reply.resolve(.success(ListeningSockets(http: http, https: https))) }
                else { reply.resolve(.failure(JerdError.unavailable(error ?? "The helper did not return standard-port sockets."))) }
            }
        }
    }

    func releaseListeners() async {
        guard connection != nil else { return }
        let _: Bool? = try? await call { proxy, reply in proxy.releaseListeners { reply.resolve(.success(true)) } }
    }

    func removeSetup() async throws {
        let previous = try await status()
        if let identity = previous.installationID, let der = previous.certificateDER, !previous.hostnames.isEmpty {
            try consent.authorize(installationID: identity, certificateDER: der, hostnames: Set(previous.hostnames))
        }
        defer { consent.clear() }
        let _: Bool = try await call(timeout: nil) { proxy, reply in
            proxy.removeSetup { error in
                if let error { reply.resolve(.failure(JerdError.unavailable(error))) }
                else { reply.resolve(.success(true)) }
            }
        }
    }

    func unregisterAfterCleanup() async throws {
        connection?.invalidate()
        connection = nil
        try await SMAppService.daemon(plistName: SystemService.plistName).unregister()
    }

    func invalidate() { connection?.invalidate(); connection = nil; connectionID = nil }

    private func connect() throws -> NSXPCConnection {
        if let connection { return connection }
        guard isEnabled() else { throw JerdError.unavailable("Approved helper setup is required.") }
        let team = try SystemService.currentTeamID()
        let id = UUID()
        let next = NSXPCConnection(machServiceName: SystemService.name, options: .privileged)
        next.remoteObjectInterface = NSXPCInterface(with: JerdHelperProtocol.self)
        next.exportedInterface = NSXPCInterface(with: JerdTrustConsentProtocol.self)
        next.exportedObject = consent
        next.setCodeSigningRequirement(try SystemService.signingRequirement(identifier: SystemService.helperIdentifier, teamID: team))
        next.invalidationHandler = { @Sendable [weak self] in Task { await self?.didInvalidate(id) } }
        next.interruptionHandler = { @Sendable [weak self] in Task { await self?.didInvalidate(id) } }
        next.resume()
        connection = next
        connectionID = id
        return next
    }

    private func didInvalidate(_ id: UUID) {
        if connectionID == id { invalidate() }
    }

    private func call<Value: Sendable>(timeout: Duration? = .seconds(20),
                                     _ send: (any JerdHelperProtocol, XPCReply<Value>) -> Void) async throws -> Value {
        let connection = try connect()
        return try await withCheckedThrowingContinuation { continuation in
            let reply = XPCReply(continuation)
            let remote = connection.remoteObjectProxyWithErrorHandler { @Sendable error in reply.resolve(.failure(error)) }
            guard let proxy = remote as? any JerdHelperProtocol else {
                reply.resolve(.failure(JerdError.unavailable("The helper interface is unavailable.")))
                return
            }
            send(proxy, reply)
            guard let timeout else { return } // The macOS authentication panel has its own Cancel action.
            Task { [weak self, id = self.connectionID] in
                try? await Task.sleep(for: timeout)
                if reply.resolve(.failure(JerdError.unavailable("The helper did not reply. Check macOS approval and try again."))) {
                    if let id { await self?.didInvalidate(id) }
                }
            }
        }
    }
}

/// An XPC failure and a reply may race. Resume each continuation once.
private final class XPCReply<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    init(_ continuation: CheckedContinuation<Value, any Error>) { self.continuation = continuation }
    @discardableResult func resolve(_ result: Result<Value, any Error>) -> Bool {
        lock.lock()
        let current = continuation
        continuation = nil
        lock.unlock()
        current?.resume(with: result)
        return current != nil
    }
}
