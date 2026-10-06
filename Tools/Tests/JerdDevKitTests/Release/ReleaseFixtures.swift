import Foundation

@testable import JerdDevKit

/// Paths and values that the release tests share.
enum ReleaseFixtures {
    /// The repository that contains this test file.
    static let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static let team = "ABCDE12345"
    static let identity = "Developer ID Application: Example (ABCDE12345)"
    static let commit = String(repeating: "a", count: 40)
}
