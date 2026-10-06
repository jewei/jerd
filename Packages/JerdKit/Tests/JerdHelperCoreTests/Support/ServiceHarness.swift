import Darwin
import Foundation
import JerdFoundation
import JerdSystem
import os

@testable import JerdHelperCore

/// A helper service on a temporary hosts file and record folder.
struct ServiceHarness {
    static let owner: uid_t = 501
    let folder: URL
    let consent = FakeConsent()
    let keychain = FakeKeychain()
    let service: HelperService

    init() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
            .appendingPathComponent("jerd-helper-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("127.0.0.1 localhost\n".utf8).write(to: folder.appendingPathComponent("hosts"))
        let inspector = FakeInspector(consent: consent)
        let store = SetupStore(
            directory: RootRecordDirectory(url: folder.appendingPathComponent("helper"), owner: getuid()),
            hosts: GuardedFileSwap(url: folder.appendingPathComponent("hosts"), expectedOwner: getuid()),
            trust: inspector)
        service = HelperService(store: store, binder: EphemeralBinder(), keychain: keychain, inspector: inspector)
    }

    func request(_ hostnames: [String] = ["demo.test"], policy: CertificateTrustPolicy = .serverTLS) throws -> Data {
        try HelperWireProtocol.encode(
            SystemRegistrationRequest(
                installationID: HelperFixture.installationID, hostnames: hostnames, certificateDER: HelperFixture.der(),
                trustPolicy: policy))
    }

    func remove() { try? FileManager.default.removeItem(at: folder) }
}
