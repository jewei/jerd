import Foundation

/// Component-wise path containment. `/a/b` contains `/a/b/c` and itself, but not `/a/bc`.
enum PathComponents {
    /// True when `inner` equals `outer` or lies below it, after removing `.` and `..` lexically.
    static func contains(_ inner: String, in outer: String) -> Bool {
        components(inner).starts(with: components(outer))
    }

    static func components(_ path: String) -> [String] {
        URL(fileURLWithPath: path).standardizedFileURL.pathComponents
    }
}
