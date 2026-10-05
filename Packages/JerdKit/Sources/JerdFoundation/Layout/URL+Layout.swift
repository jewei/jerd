import Foundation

extension URL {
    /// A child folder URL (with a trailing slash in `absoluteString`).
    func folder(_ name: String) -> URL { appendingPathComponent(name, isDirectory: true) }

    /// A child file URL.
    func file(_ name: String) -> URL { appendingPathComponent(name, isDirectory: false) }
}
