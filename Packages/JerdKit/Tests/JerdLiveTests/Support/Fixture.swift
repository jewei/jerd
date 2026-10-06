import Foundation
import JerdFoundation
import JerdTestSupport

/// Shared test data. Temporary folders come from `TemporaryDirectory`, which each test removes.
enum Fixture {
    /// The installation of `jerd-ca.der` (its common name is `Jerd Local CA <this UUID>`).
    static let installationID = UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")!

    /// A valid installation CA from the JerdSystem fixtures.
    static func certificate() throws -> Data {
        guard let url = Bundle.module.url(forResource: "Fixtures/jerd-ca", withExtension: "der") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}
