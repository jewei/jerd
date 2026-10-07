import Foundation
import JerdManifest

/// The Laravel installer: the newest stable `laravel/installer` tag. Composer resolves the package.
package struct LaravelReleaseSource: ReleaseSource {
    package static let repository = "laravel/installer"
    package let kind = RuntimeKind.laravel

    package init() {}

    package func candidates(from metadata: MetadataCache, platform: HostPlatform) async throws -> [RuntimeRelease] {
        try parse(
            await metadata.data(GitHubRelease.listURL(repository: Self.repository)), architecture: platform.architecture
        )
    }

    /// Pure: at most one candidate, the newest stable release with a `v<version>` tag.
    package func parse(_ data: Data, architecture: CPUArchitecture) throws -> [RuntimeRelease] {
        guard let release = try GitHubRelease.stableReleases(data).first,
            let version = release.version(afterOneOf: ["v"])
        else { return [] }
        return [
            RuntimeRelease(
                kind: .laravel, version: version, artifact: .composerPackage("laravel/installer"), archiveSHA256: nil,
                releasePage: try .runtime("https://github.com/\(Self.repository)/releases/tag/\(release.tag)"),
                architecture: architecture)
        ]
    }
}
