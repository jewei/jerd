import Foundation
import JerdFoundation
import JerdProcess

@testable import JerdWeb

/// An in-memory helper. `configure` approves exactly the request; steps can pause or fail.
actor FakeSystem: SystemSetupPort {
    private(set) var current: HTTPSSetupStatus
    private(set) var configurations: [HTTPSRegistration] = []
    private(set) var removals = 0
    private(set) var acquired = 0
    private(set) var released = 0
    private(set) var isPausedInAcquire = false
    private(set) var isPausedInConfigure = false
    private var pauseAcquire = false
    private var pauseConfigure = false
    private var failConfigure = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var leases: [TestListeners] = []

    init(_ status: HTTPSSetupStatus = HTTPSSetupStatus()) {
        current = status
    }

    /// An approved status for `hostnames` with the fixture CA.
    static func approved(_ hostnames: [String], policy: HTTPSTrustPolicy = .serverTLS) throws -> HTTPSSetupStatus {
        let authority = try Certificates.authority()
        return HTTPSSetupStatus(
            hostnames: hostnames.sorted(), installationID: Certificates.installationID,
            certificateSHA256: authority.fingerprint, certificateDER: authority.der, hostsConfigured: true,
            trustConfigured: true, trustPolicy: policy)
    }

    func status() -> HTTPSSetupStatus { current }

    func configure(_ registration: HTTPSRegistration) async throws {
        configurations.append(registration)
        if pauseConfigure {
            pauseConfigure = false
            isPausedInConfigure = true
            await withCheckedContinuation { waiter = $0 }
            isPausedInConfigure = false
        }
        if failConfigure {
            failConfigure = false
            throw JerdError.approvalInterrupted("Test approval failure")
        }
        current = HTTPSSetupStatus(
            hostnames: registration.hostnames, installationID: registration.installationID,
            certificateSHA256: LocalCertificateAuthority.fingerprint(of: registration.certificateDER),
            certificateDER: registration.certificateDER, hostsConfigured: true, trustConfigured: true,
            trustPolicy: registration.trustPolicy)
    }

    func acquireListeners() async throws -> InheritedListeners {
        acquired += 1
        if pauseAcquire {
            pauseAcquire = false
            isPausedInAcquire = true
            await withCheckedContinuation { waiter = $0 }
            isPausedInAcquire = false
        }
        let lease = try TestListeners()
        leases.append(lease)
        return lease.inherited
    }

    func releaseListeners() { released += 1 }

    func removeSetup() {
        removals += 1
        current = HTTPSSetupStatus()
    }

    func set(_ status: HTTPSSetupStatus) { current = status }
    func pauseNextAcquire() { pauseAcquire = true }
    func pauseNextConfigure() { pauseConfigure = true }
    func failNextConfigure() { failConfigure = true }

    func resume() {
        waiter?.resume()
        waiter = nil
    }
}

/// A trust probe that records the checked hostnames and can fail.
actor FakeProbe: TrustProbing {
    private(set) var checked: [String] = []
    var failing = false

    init(failing: Bool = false) { self.failing = failing }

    func check(hostname: String) throws {
        checked.append(hostname)
        if failing { throw JerdError.unavailable("System trust test failed") }
    }
}
