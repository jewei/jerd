import Foundation
import Testing

/// Fixed review L12: test runs reuse one fixture folder instead of leaving a new one each time.
@Suite struct FixtureFolderTests {
    @Test func separateFixtureBuildersShareOneStableBinary() async throws {
        let first = try await Fixtures().executable("sleeper")
        let second = try await Fixtures().executable("sleeper")
        #expect(first == second)
        #expect(first.deletingLastPathComponent().path == Fixtures.defaultFolder.path)
    }
}
