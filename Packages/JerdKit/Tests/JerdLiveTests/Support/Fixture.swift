import Foundation
import JerdFoundation

/// Shared test data and temporary folders.
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

    /// A new empty folder below the temporary folder. The caller removes it.
    static func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "jerd-live-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// A data layout in a new temporary folder.
    static func layout() throws -> DataLayout {
        DataLayout(root: try temporaryFolder().appendingPathComponent("Jerd", isDirectory: true))
    }
}
