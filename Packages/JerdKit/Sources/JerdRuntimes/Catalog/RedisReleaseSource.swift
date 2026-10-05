import Foundation
import JerdFoundation
import JerdManifest

/// Redis 8 or later: the official `redis/redis-hashes` list of release tarball digests.
///
/// Each line has the form `hash redis-<version>.tar.gz sha256 <hex> <url>`. Only stable versions
/// pass; release candidates such as `redis-8.10-rc1` do not parse. The first line of a version wins.
package struct RedisReleaseSource: ReleaseSource {
    package static let hashesAddress = "https://raw.githubusercontent.com/redis/redis-hashes/master/README"
    /// Redis states no size. A source tarball is about 4.5 MB.
    package static let sizeLimit: Int64 = 40_000_000
    package let kind = RuntimeKind.redis

    package init() {}

    package func candidates(from metadata: MetadataCache, platform: HostPlatform) async throws -> [RuntimeRelease] {
        try Self.parse(await metadata.text(try .runtime(Self.hashesAddress)), architecture: platform.architecture)
    }

    /// Pure: every stable Redis 8+ tarball with a valid SHA-256.
    package static func parse(_ text: String, architecture: CPUArchitecture) throws -> [RuntimeRelease] {
        var seen = Set<String>()
        var releases: [RuntimeRelease] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 4, fields[0] == "hash", fields[2] == "sha256", fields[1].hasPrefix("redis-"),
                fields[1].hasSuffix(".tar.gz"), FileDigest.isSHA256Hex(fields[3])
            else { continue }
            let version = String(fields[1].dropFirst(6).dropLast(7))
            guard let parsed = RuntimeVersion(version), parsed.components[0] >= 8, seen.insert(version).inserted
            else { continue }
            releases.append(
                RuntimeRelease(
                    kind: .redis, version: version,
                    artifact: .archive(
                        try .runtime("https://download.redis.io/releases/\(fields[1])"), size: .atMost(sizeLimit)),
                    archiveSHA256: fields[3], releasePage: try .runtime(hashesAddress), architecture: architecture))
        }
        return releases
    }
}
