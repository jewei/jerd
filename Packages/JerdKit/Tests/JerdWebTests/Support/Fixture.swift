import Foundation
import JerdFoundation

/// Files in `Tests/JerdWebTests/Fixtures`.
enum Fixture {
    static func url(_ relative: String) throws -> URL {
        guard let folder = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw JerdError.unavailable("The test fixtures are missing.")
        }
        return folder.appendingPathComponent(relative)
    }

    static func data(_ relative: String) throws -> Data {
        try Data(contentsOf: url(relative))
    }

    static func text(_ relative: String) throws -> String {
        String(decoding: try data(relative), as: UTF8.self)
    }
}
