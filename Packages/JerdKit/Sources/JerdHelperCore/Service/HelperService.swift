import Darwin
import Foundation
import JerdFoundation
import JerdSystem

/// The helper's one service, shared by every connection: the setup store and the standard ports.
///
/// One setup change or listener acquisition runs at a time across all connections. A change needs
/// the ports to be free, so it holds a reservation of ports 80 and 443 while it runs (not for a
/// removal); a bind failure stops it before any hosts or trust change. The owner of every operation
/// is the connection's effective UID; no request carries a UID, path, or command.
actor HelperService {
    private let store: SetupStore
    private let binder: any ListenerBinding
    private let keychain: any KeychainCertificateStoring
    private let inspector: any CertificateTrustInspecting
    private var ports = PortLeaseCoordinator<LoopbackListenerPair>()

    init(
        store: SetupStore, binder: any ListenerBinding, keychain: any KeychainCertificateStoring,
        inspector: any CertificateTrustInspecting
    ) {
        self.store = store
        self.binder = binder
        self.keychain = keychain
        self.inspector = inspector
    }

    /// The service on `/private/etc/hosts`, the root-owned record folder, and the system keychain.
    static func live() -> HelperService {
        let inspector = AdminTrustInspector()
        let store = SetupStore(
            directory: RootRecordDirectory(url: HelperServiceIdentity.recordDirectory, owner: 0),
            hosts: GuardedFileSwap(url: HelperServiceIdentity.hostsFile, expectedOwner: 0), trust: inspector)
        return HelperService(
            store: store, binder: StandardPortBinder(), keychain: SystemKeychainCertificates(), inspector: inspector)
    }

    func status(owner: uid_t) async throws -> Data {
        try HelperWireProtocol.encode(await store.status(ownerUID: owner))
    }

    func configure(_ data: Data, owner: uid_t, consent: any ConsentRequesting) async throws {
        let request = try HelperWireProtocol.decode(
            SystemRegistrationRequest.self, from: data, limit: HelperWireProtocol.configureLimit)
        try await mutate(.configure, reservePorts: true) {
            try await self.store.configure(request, ownerUID: owner, trust: self.installer(consent))
        }
    }

    func remove(owner: uid_t, consent: any ConsentRequesting) async throws {
        try await mutate(.remove, reservePorts: false) {
            try await self.store.remove(ownerUID: owner, trust: self.installer(consent))
        }
    }

    func recover(_ data: Data, owner: uid_t, consent: any ConsentRequesting) async throws {
        let approval = try HelperWireProtocol.decode(
            SystemRecoveryApproval.self, from: data, limit: HelperWireProtocol.recoverLimit)
        try await mutate(.recover, reservePorts: approval.action == .restorePrevious) {
            try await self.store.recover(approval, ownerUID: owner, trust: self.installer(consent))
        }
    }

    /// Ends the lease of `connection` and closes its listeners.
    func release(connection: UUID) {
        ports.release(connection: connection)?.close()
    }

    func beginAcquire(
        connection: UUID, owner: uid_t
    ) throws
        -> PortLeaseCoordinator<LoopbackListenerPair>
        .AcquireStart
    {
        try ports.beginAcquire(connection: connection, owner: owner)
    }

    func finishAcquire(connection: UUID, owner: uid_t, pair: LoopbackListenerPair?, alive: Bool) throws {
        try ports.finishAcquire(connection: connection, owner: owner, resource: pair, connectionAlive: alive)
    }

    func setupStatus(owner: uid_t) async throws -> SystemSetupStatus { try await store.status(ownerUID: owner) }

    /// Binds off the actor: a port probe can wait in `poll`, and status calls of other connections
    /// must not wait for it.
    nonisolated func bindListeners() async throws -> LoopbackListenerPair {
        let binder = binder
        return try await Task.detached { try binder.bindStandardPorts() }.value
    }

    private func installer(_ consent: any ConsentRequesting) -> TrustInstaller {
        TrustInstaller(keychain: keychain, inspector: inspector, consent: consent)
    }

    private func mutate(
        _ mutation: PortLeaseCoordinator<LoopbackListenerPair>.Mutation, reservePorts: Bool,
        _ body: () async throws -> Void
    ) async throws {
        try ports.beginMutation(mutation)
        defer { ports.endMutation() }
        let reservation = reservePorts ? try await bindListeners() : nil
        defer { reservation?.close() }
        try await body()
    }
}
