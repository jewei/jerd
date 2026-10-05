import Foundation
import JerdFoundation
import JerdManifest

/// The fields of a GitHub release that the catalog reads (`GET /repos/<owner>/<repo>/releases`).
package struct GitHubRelease: Decodable, Sendable {
    /// One release asset. GitHub states its SHA-256 as `digest: "sha256:<hex>"`.
    package struct Asset: Decodable, Sendable {
        let name: String
        let downloadURL: String
        let size: Int64
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
            case size
            case digest
        }
    }

    package let tag: String
    package let draft: Bool
    package let prerelease: Bool
    package let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case draft
        case prerelease
        case assets
    }

    /// The release list URL: the 30 most recent releases.
    package static func listURL(repository: String) throws -> URL {
        try .runtime("https://api.github.com/repos/\(repository)/releases?per_page=30")
    }

    /// Decodes a release list and keeps only published, stable releases.
    /// - Throws: `.invalid("The update source returned invalid metadata.")`.
    package static func stableReleases(_ data: Data) throws -> [GitHubRelease] {
        do {
            return try JSONDecoder().decode([GitHubRelease].self, from: data).filter { !$0.draft && !$0.prerelease }
        } catch {
            throw invalidMetadata
        }
    }

    package static var invalidMetadata: JerdError { .invalid("The update source returned invalid metadata.") }

    /// The version after one of `prefixes`, when it starts with a digit and is a stable version.
    package func version(afterOneOf prefixes: [String]) -> String? {
        for prefix in prefixes where tag.hasPrefix(prefix) {
            let rest = String(tag.dropFirst(prefix.count))
            if let first = rest.utf8.first, (48...57).contains(first), RuntimeVersion(rest) != nil {
                return rest
            }
        }
        return nil
    }
}
