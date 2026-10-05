import Foundation

/// Finds a program in a `PATH` value, as a shell would, but without a shell.
enum ExecutableLocator {
    static func find(_ name: String, searchPath: String?, isExecutable: (String) -> Bool) -> URL? {
        guard let searchPath, !name.contains("/") else { return nil }
        for directory in searchPath.split(separator: ":") where directory.hasPrefix("/") {
            let candidate = URL(filePath: String(directory)).appending(path: name)
            if isExecutable(candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
