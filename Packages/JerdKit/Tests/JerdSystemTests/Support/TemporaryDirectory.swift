import Darwin
import Foundation

/// A private temporary folder for one test.
struct TemporaryDirectory {
    let url: URL

    init() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
        url = base.appendingPathComponent("jerd-system-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    /// The names in the folder that start with `prefix`.
    func names(withPrefix prefix: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).filter { $0.hasPrefix(prefix) }.sorted()
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
