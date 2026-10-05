import Foundation
import JerdFoundation
import JerdManifest

/// Composer: the first stable entry of `https://getcomposer.org/versions` and its published checksum.
package struct ComposerReleaseSource: ReleaseSource {
    package static let versionsAddress = "https://getcomposer.org/versions"
    /// Composer states no size. A phar is about 3.6 MB.
    package static let sizeLimit: Int64 = 20_000_000
    package let kind = RuntimeKind.composer

    package init() {}

    private struct Versions: Decodable {
        struct Entry: Decodable {
            let version: String
            let path: String
        }
        let stable: [Entry]
    }

    package func candidates(from metadata: MetadataCache, platform: HostPlatform) async throws -> [RuntimeRelease] {
        let (version, url) = try Self.parseVersions(await metadata.data(try .runtime(Self.versionsAddress)))
        let checksum = try await metadata.text(try .runtime(url.absoluteString + ".sha256sum"))
        return [try Self.release(version: version, url: url, checksum: checksum, architecture: platform.architecture)]
    }

    /// The newest stable version and its download URL.
    /// - Throws: `.invalid("Composer metadata is invalid.")` unless the path is `/download/<version>/composer.phar`.
    package static func parseVersions(_ data: Data) throws -> (String, URL) {
        guard let versions = try? JSONDecoder().decode(Versions.self, from: data), let entry = versions.stable.first,
            RuntimeVersion(entry.version) != nil, entry.path == "/download/\(entry.version)/composer.phar",
            let url = URL(string: "https://getcomposer.org\(entry.path)")
        else { throw invalid }
        return (entry.version, url)
    }

    /// The release with the first token of the `.sha256sum` text as its digest.
    package static func release(
        version: String, url: URL, checksum: String, architecture: CPUArchitecture
    ) throws
        -> RuntimeRelease
    {
        guard let token = checksum.split(whereSeparator: \.isWhitespace).first, FileDigest.isSHA256Hex(String(token))
        else { throw invalid }
        return RuntimeRelease(
            kind: .composer, version: version, artifact: .archive(url, size: .atMost(sizeLimit)),
            archiveSHA256: String(token), releasePage: try .runtime(versionsAddress), architecture: architecture)
    }

    package static var invalid: JerdError { .invalid("Composer metadata is invalid.") }
}
