import Foundation
import JerdFoundation
import os

@testable import JerdSystem

/// In-memory CA trust. Each failure switch applies to the next matching call only.
final class FakeTrust: CertificateTrustInspecting, CertificateTrustChanging, Sendable {
    enum Failure: Sendable {
        case unavailable
        case partial
        case interrupted
    }

    private struct State {
        var installed: [Data: CertificateTrust] = [:]
        var nextInstallFailure: Failure?
        var nextRemovalFailure: Failure?
        var calls: [String] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func failNextInstall(_ failure: Failure) { state.withLock { $0.nextInstallFailure = failure } }
    func failNextRemoval(_ failure: Failure) { state.withLock { $0.nextRemovalFailure = failure } }
    var calls: [String] { state.withLock { $0.calls } }

    /// The installed trust of `der`, if any.
    func installed(_ der: Data) -> CertificateTrust? { state.withLock { $0.installed[der] } }

    func seed(_ trust: CertificateTrust) { state.withLock { $0.installed[trust.certificate.der] = trust } }

    func isInstalled(_ trust: CertificateTrust) throws -> Bool {
        state.withLock { current in
            guard let installed = current.installed[trust.certificate.der] else { return false }
            return installed.scope == trust.scope
        }
    }

    func install(_ trust: CertificateTrust, replacingOwned: Bool) async throws {
        try state.withLock { current in
            current.calls.append("install \(trust.policy.rawValue) \(trust.hostnames.strings.joined(separator: ","))")
            let failure = current.nextInstallFailure
            current.nextInstallFailure = nil
            switch failure {
            case .unavailable: throw JerdError.unavailable("Test trust failure")
            case .interrupted: throw JerdError.approvalInterrupted("Test app disconnect")
            case .partial:
                current.installed[trust.certificate.der] = trust
                throw JerdError.partialChange("Test partial trust failure")
            case nil: current.installed[trust.certificate.der] = trust
            }
        }
    }

    func remove(_ certificate: InstallationCertificate) async throws {
        try state.withLock { current in
            current.calls.append("remove")
            let failure = current.nextRemovalFailure
            current.nextRemovalFailure = nil
            switch failure {
            case .interrupted: throw JerdError.approvalInterrupted("Test app disconnect")
            case .unavailable: throw JerdError.unavailable("Test removal failure")
            case .partial:
                current.installed[certificate.der] = nil
                throw JerdError.unavailable("Test partial removal failure")
            case nil: current.installed[certificate.der] = nil
            }
        }
    }
}
