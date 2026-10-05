import Foundation
import JerdFoundation

/// A private engine file and its exact contents, for example `client.cnf`.
public struct EngineFile: Equatable, Sendable {
    public let url: URL
    public let contents: String

    public init(url: URL, contents: String) {
        self.url = url
        self.contents = contents
    }

    /// Writes the file atomically with mode 0600.
    public func write() throws {
        try AtomicFile.write(Data(contents.utf8), to: url)
    }

    /// A double-quoted option value: `\` becomes `\\` and `"` becomes `\"`.
    public static func quoted(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
