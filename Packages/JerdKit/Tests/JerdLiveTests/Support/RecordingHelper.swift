import Foundation
import JerdFoundation
import JerdSystem

@testable import JerdLive

/// A helper client that records every call and answers from set values. It never opens XPC.
actor RecordingHelper: HelperControlling {
    enum Call: Equatable {
        case status
        case configure(hostnames: [String], installationID: UUID, policy: CertificateTrustPolicy)
        case acquireListeners
        case releaseListeners
        case removeSetup
        case recover(id: String, action: SystemRecoveryAction)
        case approve
        case reconnect
        case unregister
        case invalidate
    }

    private(set) var calls: [Call] = []
    var statusResult: Result<HelperStatus, JerdError> = .success(
        HelperStatus(availability: .notRegistered, setup: .empty))
    var failure: JerdError?

    init(status: HelperStatus? = nil) {
        if let status { statusResult = .success(status) }
    }

    func setStatus(_ status: HelperStatus) { statusResult = .success(status) }
    func setFailure(_ error: JerdError?) { failure = error }

    func status() throws -> HelperStatus {
        calls.append(.status)
        return try statusResult.get()
    }

    func configure(
        hostnames: ValidatedHostnames, caCertificate: JerdSystem.InstallationCertificate, policy: CertificateTrustPolicy
    ) throws {
        calls.append(
            .configure(
                hostnames: hostnames.values.map(\.value), installationID: caCertificate.installationID, policy: policy))
        try failIfSet()
    }

    func acquireListeners() throws -> LoopbackListenerPair {
        calls.append(.acquireListeners)
        try failIfSet()
        return try LoopbackListenerPair.bind(httpPort: 0, httpsPort: 0)
    }

    func releaseListeners() { calls.append(.releaseListeners) }

    func removeSetup() throws {
        calls.append(.removeSetup)
        try failIfSet()
    }

    func recover(report: SystemRecoveryStatus, action: SystemRecoveryAction) throws {
        calls.append(.recover(id: report.id, action: action))
        try failIfSet()
    }

    func approve() throws {
        calls.append(.approve)
        try failIfSet()
    }

    func reconnect() throws {
        calls.append(.reconnect)
        try failIfSet()
    }

    func unregister() throws {
        calls.append(.unregister)
        try failIfSet()
    }

    func invalidate() { calls.append(.invalidate) }

    private func failIfSet() throws {
        if let failure { throw failure }
    }
}
