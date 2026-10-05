import Foundation
import JerdFoundation
import JerdManifest
import JerdProcess
import JerdRuntimes

/// A hermetic cloudflared release: a tar archive served by a fake fetcher, its pinned license, and
/// a command runner that answers the version probe.
struct CloudflaredFixture {
    let archive: Data
    let release: RuntimeRelease
    let fetcher: FakeFetcher
    let commands: ScriptedCommandRunner

    init(version: String = "2026.9.3", probeOutput: String? = nil, delay: Duration? = nil) throws {
        var tar = TarBuilder()
        tar.file("cloudflared", "#!/bin/sh\necho cloudflared\n", mode: "0000755")
        tar.file("README.md", "not selected")
        archive = tar.data
        let url = try URL.runtime(
            "https://github.com/cloudflare/cloudflared/releases/download/\(version)/cloudflared-darwin-arm64.tgz")
        release = RuntimeRelease(
            kind: .cloudflared, version: version, artifact: .archive(url, size: .exact(Int64(archive.count))),
            archiveSHA256: FileDigest.hexSHA256(of: archive),
            releasePage: try .runtime("https://github.com/cloudflare/cloudflared/releases"), architecture: .arm64)
        guard let license = try PinnedLicense.of(.cloudflared) else {
            throw JerdError.invalid("No cloudflared license pin.")
        }
        fetcher = FakeFetcher(
            [url: archive, license.url: try Fixture.data("Licenses/cloudflared-LICENSE")], delay: delay)
        let output = probeOutput ?? "cloudflared version \(version) (built today)"
        commands = ScriptedCommandRunner { _ in CommandResult(status: 0, output: output) }
    }

    func installer(directory: URL) -> RuntimeInstaller {
        RuntimeInstaller(
            directory: directory, fetcher: fetcher, commands: commands,
            policy: ReleasePolicy(platform: HostPlatform(architecture: .arm64, osMajor: 15)))
    }
}
