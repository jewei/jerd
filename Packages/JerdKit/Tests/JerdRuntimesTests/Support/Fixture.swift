import Foundation
import Testing

/// Saved publisher responses and other golden files.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func text(_ name: String) throws -> String { String(decoding: try data(name), as: UTF8.self) }

    /// A repository file, for example the committed pin catalog.
    static func repositoryFile(_ relative: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../../")
            .appendingPathComponent(relative).standardizedFileURL
    }
}
