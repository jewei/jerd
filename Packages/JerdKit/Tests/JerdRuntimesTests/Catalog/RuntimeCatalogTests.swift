import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

@Suite struct RuntimeCatalogTests {
    private let policy = ReleasePolicy(platform: HostPlatform(architecture: .arm64, osMajor: 15))
    private let checkedAt = Date(timeIntervalSince1970: 1_000)

    private func list(_ repository: String) throws -> URL {
        try #require(URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=30"))
    }

    @Test func checkReturnsInstallableReleasesNewestFirst() async throws {
        let fetcher = FakeFetcher([
            try list("caddyserver/caddy"): try Fixture.data("Catalog/github-caddyserver_caddy.json")
        ])
        let catalog = RuntimeCatalog(fetcher: fetcher, policy: policy) { checkedAt }
        let check = await catalog.check(.caddy)
        #expect(check.error == nil && check.checkedAt == checkedAt)
        #expect(check.releases.map(\.version) == ["2.11.7", "2.11.6", "2.11.4", "2.11.3", "2.11.2", "2.11.1"])
    }

    @Test func oneInvalidCandidateDoesNotHideTheValidOnes() async throws {
        var data = try Fixture.text("Catalog/github-lerd-env_php.json")
        data = data.replacingOccurrences(of: "\"size\": 66723803", with: "\"size\": 900000000")
        let fetcher = FakeFetcher([try list("lerd-env/php"): Data(data.utf8)])
        let check = await RuntimeCatalog(fetcher: fetcher, policy: policy).check(.php)
        #expect(check.error == nil)
        #expect(!check.releases.map(\.version).contains("8.5.11"))
        #expect(check.releases.first?.version == "8.5.10")
    }

    @Test func versionsSortNumericallyNotAsText() async throws {
        let readme =
            "hash redis-8.8.3.tar.gz sha256 \(digest("a")) x\nhash redis-8.10.2.tar.gz sha256 \(digest("b")) x\n"
        let url = try #require(URL(string: "https://raw.githubusercontent.com/redis/redis-hashes/master/README"))
        let check = await RuntimeCatalog(fetcher: FakeFetcher([url: Data(readme.utf8)]), policy: policy).check(.redis)
        #expect(check.releases.map(\.version) == ["8.10.2", "8.8.3"])
    }

    @Test func noInstallableCandidateIsAnError() async throws {
        let fetcher = FakeFetcher([try list("lerd-env/php"): Data("[]".utf8)])
        let check = await RuntimeCatalog(fetcher: fetcher, policy: policy).check(.php)
        #expect(check.releases.isEmpty)
        #expect(check.error == "No supported stable macOS package is available from this source.")
    }

    @Test func fetchFailureIsReturnedAsData() async {
        let check = await RuntimeCatalog(fetcher: FakeFetcher(), policy: policy).check(.mailpit)
        #expect(check.error == "The update source returned HTTP 404.")
    }

    @Test func everyKindHasASource() async throws {
        // Without metadata every check fails cleanly; none crashes or hangs.
        let catalog = RuntimeCatalog(fetcher: FakeFetcher(), policy: policy)
        for kind in RuntimeKind.allCases {
            #expect(await catalog.check(kind).error != nil)
        }
    }
}
