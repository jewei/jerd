import Darwin
import Foundation
import JerdFoundation
import JerdSystem
import os

@testable import JerdHelperCore

/// The CA fixture (copy of `JerdSystemTests/Fixtures/Certificates/jerd-ca.der`).
enum HelperFixture {
    static let installationID = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!

    static func der() throws -> Data {
        guard let url = Bundle.module.url(forResource: "Fixtures/jerd-ca", withExtension: "der") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    static func trust(
        _ hostnames: [String] = ["demo.test"], policy: CertificateTrustPolicy = .serverTLS
    ) throws
        -> CertificateTrust
    {
        CertificateTrust(
            certificate: try InstallationCertificate(installationID: installationID, der: der()),
            hostnames: try ValidatedHostnames(hostnames), policy: policy)
    }
}
