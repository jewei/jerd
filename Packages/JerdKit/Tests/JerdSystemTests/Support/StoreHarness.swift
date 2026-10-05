import Darwin
import Foundation
import JerdFoundation

@testable import JerdSystem

/// A setup store on a temporary hosts file and a temporary record folder, with in-memory trust.
struct StoreHarness {
    static let owner: uid_t = 501
    static let originalHosts = Data("127.0.0.1 localhost\n".utf8)

    let folder: TemporaryDirectory
    let hostsURL: URL
    let directory: RootRecordDirectory
    let trust = FakeTrust()

    init(hosts: Data = StoreHarness.originalHosts) throws {
        folder = try TemporaryDirectory()
        hostsURL = folder.path("hosts")
        try hosts.write(to: hostsURL)
        directory = RootRecordDirectory(url: folder.path("helper"), owner: getuid())
    }

    func store(hooks: GuardedFileSwapHooks = GuardedFileSwapHooks()) -> SetupStore {
        SetupStore(directory: directory, hosts: hostsFile(hooks: hooks), trust: trust)
    }

    func hostsFile(hooks: GuardedFileSwapHooks = GuardedFileSwapHooks()) -> GuardedFileSwap {
        GuardedFileSwap(url: hostsURL, expectedOwner: getuid(), lockTimeout: .milliseconds(200), hooks: hooks)
    }

    func request(
        _ hostnames: [String], policy: CertificateTrustPolicy = .serverTLS, certificate: String = "jerd-ca"
    )
        throws -> SystemRegistrationRequest
    {
        let id = certificate == "jerd-ca" ? Fixture.installationID : Fixture.otherInstallationID
        return SystemRegistrationRequest(
            installationID: id, hostnames: hostnames, certificateDER: try Fixture.certificate(certificate),
            trustPolicy: policy)
    }

    var hosts: Data { (try? Data(contentsOf: hostsURL)) ?? Data() }
    func record(_ file: RootRecordDirectory.File) -> Data? { try? Data(contentsOf: directory.location(of: file)) }

    func remove() { folder.remove() }
}
