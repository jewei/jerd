import Foundation
import Testing

/// Golden files that older Jerd builds and Sparkle wrote, copied byte for byte.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// A repository file, for example the committed pin catalog.
    static func repositoryFile(_ relative: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../../")
            .appendingPathComponent(relative).standardizedFileURL
    }
}

/// A SHA-256 text made of one repeated hexadecimal digit.
func digest(_ character: Character) -> String { String(repeating: character, count: 64) }
