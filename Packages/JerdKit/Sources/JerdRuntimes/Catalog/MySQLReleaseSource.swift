import Foundation
import JerdFoundation
import JerdManifest

/// MySQL 8.4 LTS: the macOS tarballs that Oracle's download page lists.
///
/// Oracle publishes no machine-readable list, so the page is read for file names of the form
/// `mysql-8.4.<n>-macos<major>-<arch>.tar.gz`. Every archive must also pass Oracle's OpenPGP
/// signature check with the pinned key before it is used.
package struct MySQLReleaseSource: ReleaseSource {
    package static let pageAddress = "https://dev.mysql.com/downloads/mysql/8.4.html?os=33"
    /// Oracle states no size on the page. A tarball is about 170 MB.
    package static let sizeLimit: Int64 = 500_000_000
    package let kind = RuntimeKind.mysql

    package init() {}

    package func candidates(from metadata: MetadataCache, platform: HostPlatform) async throws -> [RuntimeRelease] {
        try Self.parse(await metadata.text(try .runtime(Self.pageAddress)), platform: platform)
    }

    /// Pure: compatible packages in page order. A version appears once: the first package that this
    /// macOS can run wins (filter first, then de-duplicate).
    /// - Throws: `.unavailable` when the page lists no MySQL 8.4 macOS package at all (the page changed).
    package static func parse(_ page: String, platform: HostPlatform) throws -> [RuntimeRelease] {
        let architecture = platform.architecture.rawValue
        let pattern = #"mysql-(8\.4\.[0-9]+)-macos(1[5-9]|[2-9][0-9])-"# + architecture + #"\.tar\.gz"#
        let matches = page.matches(of: try Regex(pattern))
        guard !matches.isEmpty else {
            throw JerdError.unavailable(
                "The MySQL download page changed. Jerd found no MySQL 8.4 package for this Mac.")
        }
        var seen = Set<String>()
        var releases: [RuntimeRelease] = []
        for match in matches {
            guard let version = match.output[1].substring.map(String.init),
                let minimumOS = match.output[2].substring.flatMap({ Int($0) }),
                minimumOS <= platform.osMajor, seen.insert(version).inserted
            else { continue }
            let file = String(match.output[0].substring ?? "")
            let url = try URL.runtime("https://cdn.mysql.com/Downloads/MySQL-8.4/\(file)")
            releases.append(
                RuntimeRelease(
                    kind: .mysql, version: version, artifact: .archive(url, size: .atMost(sizeLimit)),
                    archiveSHA256: nil, signatureURL: try .runtime(url.absoluteString + ".asc"),
                    releasePage: try .runtime(pageAddress), architecture: platform.architecture,
                    minimumOSMajor: minimumOS))
        }
        return releases
    }
}
