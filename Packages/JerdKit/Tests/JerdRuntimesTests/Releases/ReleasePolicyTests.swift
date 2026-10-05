import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing

@Suite struct ReleasePolicyTests {
    private let policy = ReleasePolicy(platform: HostPlatform(architecture: .arm64, osMajor: 15))
    private let page = URL(string: "https://github.com/lerd-env/php/releases") ?? URL(fileURLWithPath: "/")
    private let asset =
        URL(string: "https://github.com/lerd-env/php/releases/download/a.tar.gz")
        ?? URL(fileURLWithPath: "/")

    private func release(
        _ kind: RuntimeKind = .php, version: String = "8.5.11", artifact: ReleaseArtifact? = nil,
        sha256: String? = digest("a"), signature: URL? = nil, architecture: CPUArchitecture = .arm64,
        minimumOS: Int? = nil
    ) -> RuntimeRelease {
        RuntimeRelease(
            kind: kind, version: version, artifact: artifact ?? .archive(asset, size: .exact(10)),
            archiveSHA256: sha256, signatureURL: signature, releasePage: page, architecture: architecture,
            minimumOSMajor: minimumOS)
    }

    @Test func digestPinnedArchiveIsAccepted() {
        #expect(policy.check(release()) == nil)
    }

    @Test func idsSeparateBuildsOfOneVersion() {
        #expect(release(sha256: digest("a")).id != release(sha256: digest("b")).id)
        #expect(release(sha256: digest("a")).id == "php-8.5.11-\(digest("a"))")
        #expect(release(.mysql, sha256: nil, signature: page).id == "mysql-8.5.11")
    }

    @Test func malformedMetadataIsIncomplete() {
        #expect(policy.check(release(version: "8.6.0RC1")) == .incomplete)
        #expect(policy.check(release(sha256: "ABC")) == .incomplete)
        #expect(policy.check(release(artifact: .archive(asset, size: .exact(0)))) == .incomplete)
        #expect(policy.check(release(artifact: .archive(asset, size: .atMost(800_000_001)))) == .incomplete)
        #expect(policy.check(release(artifact: .archive(asset, size: .atMost(800_000_000)))) == nil)
    }

    @Test func onlyPinnedPublisherSignaturesReplaceADigest() {
        #expect(policy.check(release(.mysql, sha256: nil, signature: page)) == nil)
        #expect(policy.check(release(.mysql, sha256: nil)) == .unverifiable)
        #expect(policy.check(release(.redis, sha256: nil, signature: page)) == .unverifiable)
        #expect(policy.check(release(.redis, sha256: digest("a"), signature: page)) == .unverifiable)
    }

    @Test func composerArtifactsBelongToTheLaravelInstallerOnly() throws {
        #expect(policy.check(release(.laravel, artifact: .composerPackage("laravel/installer"), sha256: nil)) == nil)
        #expect(policy.check(release(.php, artifact: .composerPackage("x"), sha256: nil)) == .unverifiable)
        let project = ReleaseArtifact.lockedComposerProject(URL(fileURLWithPath: "/repo/Runtimes/laravel"))
        #expect(policy.check(release(.laravel, artifact: project, sha256: digest("a"))) == nil)
        #expect(policy.check(release(.laravel, artifact: project, sha256: nil)) == .unverifiable)
    }

    @Test func urlsOutsideTheAllowlistAreRefused() throws {
        let other = try #require(URL(string: "https://example.com/a.tar.gz"))
        #expect(policy.check(release(artifact: .archive(other, size: .exact(10)))) == .unsupportedURL)
        #expect(policy.check(release(.mysql, sha256: nil, signature: other)) == .unsupportedURL)
    }

    @Test func otherArchitecturesAndNewerSystemsAreIncompatible() throws {
        #expect(policy.check(release(architecture: .intel)) == .incompatible)
        #expect(policy.check(release(minimumOS: 16)) == .incompatible)
        #expect(policy.check(release(minimumOS: 15)) == nil)
        #expect(throws: JerdError.unavailable("This runtime package is not compatible with this Mac.")) {
            try policy.validate(release(architecture: .intel))
        }
    }

    @Test func rejectionsHaveTheUserMessages() {
        #expect(ReleaseRejection.incomplete.error == .invalid("The update metadata is incomplete or invalid."))
        #expect(ReleaseRejection.unverifiable.error == .invalid("The runtime download has no verification method."))
        #expect(ReleaseRejection.unsupportedURL.error == .invalid("The update source has an unsupported download URL."))
    }

    @Test func verificationLabelSaysWhatIsChecked() {
        #expect(release().verification == .digest(digest("a")))
        #expect(release(.mysql, sha256: nil, signature: page).verification == .publisherSignature)
        #expect(
            release(.laravel, artifact: .composerPackage("laravel/installer"), sha256: nil).verification
                == .composerLock)
        #expect(release(.postgresql, version: "2.9.6").versionLabel == "Postgres.app 2.9.6")
    }
}
