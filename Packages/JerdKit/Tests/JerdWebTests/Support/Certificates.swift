import Foundation
import JerdFoundation

@testable import JerdWeb

/// The certificate fixtures. `installation-ca.pem` is the root CA of `installationID`.
enum Certificates {
    static let installationID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    static func pem(_ name: String = "installation-ca") throws -> Data {
        try Fixture.data("certificates/\(name).pem")
    }

    static func authority(_ name: String = "installation-ca") throws -> LocalCertificateAuthority {
        try LocalCertificateAuthority(pem: try pem(name))
    }

    /// Writes the installation ID and the CA of the fixture into an environment folder.
    static func install(in environment: EnvironmentLayout, name: String = "installation-ca") throws {
        try OwnedDirectory.create(environment.root)
        try AtomicFile.write(Data(installationID.uuidString.utf8), to: environment.installationIDFile)
        try OwnedDirectory.create(environment.rootCertificateFile.deletingLastPathComponent())
        try AtomicFile.write(try pem(name), to: environment.rootCertificateFile)
    }
}
