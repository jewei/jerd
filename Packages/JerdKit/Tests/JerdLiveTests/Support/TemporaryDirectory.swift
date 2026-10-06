import Darwin
import Foundation
import JerdFoundation

/// A private temporary folder for one test. The test removes it with `defer { folder.remove() }`,
/// so the folder goes away also when the test fails (review final-domain-r1 L2).
struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "jerd-live-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        chmod(url.path, 0o700)
    }

    /// A data layout in `Jerd/` below the folder. Nothing is created until a test writes.
    var layout: DataLayout { DataLayout(root: url.appendingPathComponent("Jerd", isDirectory: true)) }

    func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    func remove() { try? FileManager.default.removeItem(at: url) }
}
