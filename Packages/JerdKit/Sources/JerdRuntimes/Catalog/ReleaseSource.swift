import Foundation
import JerdManifest

/// The publisher catalog of one runtime kind. A source reads metadata and returns candidates;
/// the release policy decides which candidates are installable.
package protocol ReleaseSource: Sendable {
    var kind: RuntimeKind { get }

    /// Reads the publisher metadata through the cache and returns every recognized candidate.
    func candidates(from metadata: MetadataCache, platform: HostPlatform) async throws -> [RuntimeRelease]
}

extension URL {
    /// A URL from text that the catalog builds from publisher data.
    /// - Throws: `.invalid("The update source has an unsupported download URL.")` for text that is not a URL.
    package static func runtime(_ text: String) throws -> URL {
        guard let url = URL(string: text) else { throw HostAllowlist.unsupported }
        return url
    }
}
