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
    static let sha1 = "0123456789ABCDEF0123456789ABCDEF01234567"
    static let otherSHA1 = "89ABCDEF0123456789ABCDEF0123456789ABCDEF"
    static let commit = String(repeating: "a", count: 40)

    /// `security find-identity -v -p codesigning` with one Developer ID identity of the test team and
    /// one identity of another team.
    static let identities = """
          1) \(sha1) "\(identity)"
          2) FEDCBA9876543210FEDCBA9876543210FEDCBA98 "Developer ID Application: Other (ZZZZZ99999)"
             2 valid identities found

        """

    static func request(
        version: String = "0.2.0", build: String = "3", minimum: String? = "14.0", prepareOnly: Bool = false
    ) -> ReleaseRequest {
        ReleaseRequest(
            version: version, build: build, minimumMacOS: minimum, team: team, notaryProfile: "notary",
            prepareOnly: prepareOnly)
    }

    static func inputs(
        version: String = "0.2.0", build: String = "3", minimum: String? = "14.0", prepareOnly: Bool = false
    ) throws -> ReleaseInputs {
        try ReleaseInputs.parse(
            request(version: version, build: build, minimum: minimum, prepareOnly: prepareOnly),
            deploymentTarget: ReleaseVersion("14.0")!, identities: identities)
    }
}
