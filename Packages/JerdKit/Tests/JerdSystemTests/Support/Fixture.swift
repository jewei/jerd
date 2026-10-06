import Foundation
import JerdFoundation

/// Test fixtures: CA certificates made with `openssl` and JSON that the old helper code wrote.
enum Fixture {
    /// The installation of `jerd-ca.der` (its common name is `Jerd Local CA <this UUID>`).
    static let installationID = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!
    /// The installation of `jerd-ca-other.der`.
    static let otherInstallationID = UUID(uuidString: "3F2504E0-4F89-41D3-9A0C-0305E82C3301")!

    static func data(_ path: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(path)", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: path])
        }
        return try Data(contentsOf: url)
    }

    static func certificate(_ name: String = "jerd-ca") throws -> Data { try data("Certificates/\(name).der") }

    static func hostnames(_ names: String...) throws -> [Hostname] { try names.map { try Hostname($0) } }
}
