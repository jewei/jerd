import Foundation
import JerdFoundation

/// The live project file reader. Its canonical form is the saved form of `projectPath` and `documentRoot`.
///
/// Compatibility: Foundation's `resolvingSymlinksInPath` drops a leading `/private` when the shorter
/// path also exists (`/private/tmp/x` becomes `/tmp/x`). Saved paths use that form, so duplicate
/// detection and CLI matching depend on it. Do not replace it with `realpath`.
public struct PathCanonicalizer: ProjectFileInspecting {
    public init() {}

    public func canonicalDirectory(_ path: String) throws -> String {
        guard path.hasPrefix("/"), !path.unicodeScalars.contains(where: { $0.value < 32 }) else {
            throw JerdError.invalid("Use an absolute directory path without control characters.")
        }
        let resolved = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { throw JerdError.invalid("Directory does not exist: \(path)") }
        return resolved.path
    }

    public func isFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}
