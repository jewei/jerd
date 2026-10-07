import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

/// Opt-in checks against the real publishers: `JERD_RUNTIME_NETWORK=1`. They download metadata
/// only, except the license check, which fetches three small text files.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["JERD_RUNTIME_NETWORK"] == "1"))
struct LiveCatalogTests {
    @Test func everyPublisherOffersAnInstallableRelease() async {
        let catalog = RuntimeCatalog(fetcher: URLSessionFetcher())
        for kind in RuntimeKind.allCases {
            let check = await catalog.check(kind)
            #expect(check.error == nil, "\(kind.title): \(check.error ?? "")")
            #expect(!check.releases.isEmpty, "\(kind.title)")
        }
    }

    @Test(arguments: [RuntimeKind.composer, .rustfs, .cloudflared])
    func pinnedLicensesStillHaveTheirReviewedText(_ kind: RuntimeKind) async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let license = try #require(try PinnedLicense.of(kind))
        try await license.fetch(to: folder.path("LICENSE"), using: URLSessionFetcher())
    }
}
