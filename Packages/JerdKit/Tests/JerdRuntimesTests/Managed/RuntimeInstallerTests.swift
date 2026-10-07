import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import Testing
import os

@Suite struct RuntimeInstallerTests {
    @Test func installPreparesProbesAndCommitsAnImmutableBuild() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let fixture = try CloudflaredFixture()
        let messages = OSAllocatedUnfairLock(initialState: [String]())
        let runtime = try await fixture.installer(directory: folder.url).install(fixture.release) { report in
            messages.withLock { $0.append(report.message) }
        }
        let sha = try #require(fixture.release.archiveSHA256)
        #expect(runtime.folderName == "cloudflared-2026.9.3-arm64-\(sha)")
        #expect(runtime.executable.lastPathComponent == "cloudflared" && runtime.secondaryExecutable == nil)
        #expect(permissions(runtime.executable) == 0o700)
        #expect(permissions(runtime.directory.appendingPathComponent("LICENSE")) == 0o600)
        #expect(permissions(runtime.directory) == 0o700)
        #expect(FileProbe.presence(at: runtime.directory.appendingPathComponent("README.md")) == .absent)
        let receipt = try BuildReceipt.decode(
            Data(contentsOf: runtime.directory.appendingPathComponent("update-receipt.json")))
        #expect(Set(receipt.files.keys) == ["cloudflared", "LICENSE"])
        #expect(receipt.archiveSHA256 == sha && receipt.version == "2026.9.3")
        #expect(fixture.commands.commandLines == [["cloudflared", "--version"]])
        #expect(messages.withLock { $0 }.first == "Downloading Cloudflare Tunnel 2026.9.3…")
        #expect(messages.withLock { $0 }.last == "Installed Cloudflare Tunnel 2026.9.3.")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path) == [runtime.folderName])
    }

    @Test func installedBuildIsReusedWithoutAnotherDownload() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let fixture = try CloudflaredFixture()
        let installer = fixture.installer(directory: folder.url)
        let first = try await installer.install(fixture.release)
        let requests = fixture.fetcher.requests.count
        let second = try await installer.install(fixture.release)
        #expect(first == second)
        #expect(fixture.fetcher.requests.count == requests)
        #expect(await installer.list().compactMap(\.runtime) == [first])
    }

    @Test func digestMismatchLeavesNothingBehind() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let fixture = try CloudflaredFixture()
        let wrong = RuntimeRelease(
            kind: .cloudflared, version: "2026.9.3", artifact: fixture.release.artifact, archiveSHA256: digest("e"),
            releasePage: fixture.release.releasePage, architecture: .arm64)
        let message =
            "The Cloudflare Tunnel 2026.9.3 download does not match its expected SHA-256. Jerd installed nothing."
        await #expect(throws: JerdError.invalid(message)) {
            try await fixture.installer(directory: folder.url).install(wrong)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path).isEmpty)
    }

    @Test(arguments: ["cloudflared version 2026.9.30", "other version 2026.9.3"])
    func wrongReportedVersionFailsTheInstallation(_ output: String) async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let fixture = try CloudflaredFixture(probeOutput: output)
        await #expect(throws: JerdError.invalid("The installed Cloudflare Tunnel did not report the expected version."))
        {
            try await fixture.installer(directory: folder.url).install(fixture.release)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path).isEmpty)
    }

    @Test func changedLicenseTextIsRefused() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let fixture = try CloudflaredFixture()
        let license = try #require(try PinnedLicense.of(.cloudflared))
        fixture.fetcher.set(license.url, Data("a different license".utf8))
        await #expect(throws: JerdError.self) {
            try await fixture.installer(directory: folder.url).install(fixture.release)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path).isEmpty)
    }

    @Test func secondInstallationWaitsForTheFirst() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let fixture = try CloudflaredFixture(delay: .milliseconds(300))
        let installer = fixture.installer(directory: folder.url)
        let first = Task { try await installer.install(fixture.release) }
        try await Task.sleep(for: .milliseconds(50))
        await #expect(throws: JerdError.unavailable("Wait for the current runtime installation to finish.")) {
            try await installer.install(fixture.release)
        }
        _ = try await first.value
    }

    @Test func cancelledInstallationLeavesNoBuildAndNoStaging() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let fixture = try CloudflaredFixture(delay: .seconds(5))
        let installer = fixture.installer(directory: folder.url)
        let task = Task { try await installer.install(fixture.release) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path).isEmpty)
    }

    /// The reuse check hashes the installed build on a GCD thread; a cancellation must stop that hash.
    @Test func cancellationStopsTheVerificationOfAnInstalledBuildWhileItRuns() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let fixture = try CloudflaredFixture()
        let sha = try #require(fixture.release.archiveSHA256)
        let build = folder.path("cloudflared-2026.9.3-arm64-\(sha)")
        try makeSparseFile(build.appendingPathComponent("cloudflared"))
        let receipt = BuildReceipt(
            kind: .cloudflared, version: "2026.9.3", releaseVersion: "2026.9.3", archiveSHA256: sha,
            executable: try #require(RelativePath("cloudflared")), secondaryExecutable: nil,
            files: [try #require(RelativePath("cloudflared")): digest("0")])
        try AtomicFile.write(try receipt.encoded(), to: build.appendingPathComponent(BuildReceipt.fileName))
        let installer = fixture.installer(directory: folder.url)
        let result = await cancelWhileRunning { try await installer.install(fixture.release) }
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(fixture.fetcher.requests.isEmpty)
        #expect(FileProbe.presence(at: build.appendingPathComponent("cloudflared")) == .present)
    }

    @Test func incompatibleReleaseIsRefusedBeforeAnyDownload() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let fixture = try CloudflaredFixture()
        let intel = RuntimeRelease(
            kind: .cloudflared, version: "2026.9.3", artifact: fixture.release.artifact,
            archiveSHA256: fixture.release.archiveSHA256, releasePage: fixture.release.releasePage, architecture: .intel
        )
        await #expect(throws: JerdError.unavailable("This runtime package is not compatible with this Mac.")) {
            try await fixture.installer(directory: folder.url).install(intel)
        }
        #expect(fixture.fetcher.requests.isEmpty)
    }

    @Test func mysqlArchiveNeedsAValidOracleSignatureEvenWithADigest() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let archive = Data("mysql archive".utf8)
        let url = try URL.runtime("https://cdn.mysql.com/Downloads/MySQL-8.4/mysql-8.4.11-macos15-arm64.tar.gz")
        let signature = try URL.runtime(url.absoluteString + ".asc")
        let fetcher = FakeFetcher([url: archive, signature: Data("-----BEGIN PGP SIGNATURE-----\nAAAA\n".utf8)])
        let release = RuntimeRelease(
            kind: .mysql, version: "8.4.11", artifact: .archive(url, size: .exact(Int64(archive.count))),
            archiveSHA256: FileDigest.hexSHA256(of: archive), signatureURL: signature,
            releasePage: try .runtime("https://dev.mysql.com/downloads/mysql/8.4.html"), architecture: .arm64)
        let installer = RuntimeInstaller(
            directory: folder.url, fetcher: fetcher, commands: ScriptedCommandRunner(),
            policy: ReleasePolicy(platform: HostPlatform(architecture: .arm64, osMajor: 15)))
        await #expect(throws: JerdError.invalid(PinnedRSAKey.mysqlRelease2025.failureMessage)) {
            try await installer.install(release)
        }
        #expect(fetcher.requests == [url, signature])
    }

    /// A pinned MySQL release whose signature pin names `signatureSHA256` and `sizeLimit`.
    private func pinnedMySQL(
        signature: Data, signatureSHA256: String, sizeLimit: Int64 = 900
    ) throws -> (RuntimeRelease, FakeFetcher, [URL]) {
        let archive = Data("mysql archive".utf8)
        let url = try URL.runtime("https://cdn.mysql.com/Downloads/MySQL-8.4/mysql-8.4.11-macos15-arm64.tar.gz")
        let signatureURL = try URL.runtime(url.absoluteString + ".asc")
        let release = RuntimeRelease(
            kind: .mysql, version: "8.4.11", artifact: .archive(url, size: .exact(Int64(archive.count))),
            archiveSHA256: FileDigest.hexSHA256(of: archive), signatureURL: signatureURL,
            releasePage: try .runtime("https://dev.mysql.com/downloads/mysql/8.4.html"), architecture: .arm64,
            pinnedSignature: PinnedFile(url: signatureURL, sizeLimit: sizeLimit, sha256: signatureSHA256))
        return (release, FakeFetcher([url: archive, signatureURL: signature]), [url, signatureURL])
    }

    private func mysqlInstaller(_ folder: TemporaryFolder, _ fetcher: FakeFetcher) -> RuntimeInstaller {
        RuntimeInstaller(
            directory: folder.url, fetcher: fetcher, commands: ScriptedCommandRunner(),
            policy: ReleasePolicy(platform: HostPlatform(architecture: .arm64, osMajor: 15)))
    }

    /// The pinned signature digest is enforced before the OpenPGP check.
    @Test func pinnedSignatureWithAnotherDigestIsRefused() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let signature = Data("-----BEGIN PGP SIGNATURE-----\nAAAA\n".utf8)
        let (release, fetcher, urls) = try pinnedMySQL(signature: signature, signatureSHA256: digest("d"))
        await #expect(throws: JerdError.invalid("The MySQL signature file does not match its reviewed pin.")) {
            try await mysqlInstaller(folder, fetcher).install(release)
        }
        #expect(fetcher.requests == urls)
    }

    @Test func pinnedSignatureWithItsDigestStillNeedsAValidOpenPGPSignature() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let signature = Data("-----BEGIN PGP SIGNATURE-----\nAAAA\n".utf8)
        let (release, fetcher, _) = try pinnedMySQL(
            signature: signature, signatureSHA256: FileDigest.hexSHA256(of: signature))
        await #expect(throws: JerdError.invalid(PinnedRSAKey.mysqlRelease2025.failureMessage)) {
            try await mysqlInstaller(folder, fetcher).install(release)
        }
    }

    @Test func pinnedSignatureSizeLimitIsEnforced() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let signature = Data(repeating: 65, count: 64)
        let (release, fetcher, _) = try pinnedMySQL(
            signature: signature, signatureSHA256: FileDigest.hexSHA256(of: signature), sizeLimit: 32)
        await #expect(throws: JerdError.invalid("The download exceeds its size limit or is empty.")) {
            try await mysqlInstaller(folder, fetcher).install(release)
        }
    }

    @Test func abandonedStagingFoldersAreRemoved() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        try folder.write("partial", to: ".install-ABC/payload/file")
        try folder.write("keep", to: "php-8.5.11-arm64/file")
        let installer = try CloudflaredFixture().installer(directory: folder.url)
        #expect(await installer.removeAbandonedStaging() == [".install-ABC"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path) == ["php-8.5.11-arm64"])
    }
}
