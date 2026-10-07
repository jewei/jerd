import Foundation
import JerdFoundation

/// A private engine file and its exact contents, for example `client.cnf`.
package struct EngineFile: Equatable, Sendable {
    package let url: URL
    package let contents: String

    package init(url: URL, contents: String) {
        self.url = url
        self.contents = contents
    }

    /// Writes the file atomically with mode 0600.
    package func write() throws {
        try AtomicFile.write(Data(contents.utf8), to: url)
    }

    /// A double-quoted option value: `\` becomes `\\` and `"` becomes `\"`.
    package static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
