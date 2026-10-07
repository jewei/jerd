import Foundation
import JerdFoundation
import JerdManifest

/// A license text that Jerd copies into a payload, fetched from a fixed URL and checked by SHA-256.
///
/// The licenses of these projects do not change between releases, so one reviewed copy serves
/// every version. A changed text fails the installation instead of shipping unreviewed content.
public struct PinnedLicense: Sendable, Equatable {
    public let url: URL
    public let sha256: String
    /// The largest accepted size in bytes.
    public static let sizeLimit = 1_000_000

    public init(url: URL, sha256: String) {
        self.url = url
        self.sha256 = sha256
    }

    /// The pinned license of a kind whose archive has no license file, or nil.
    public static func of(_ kind: RuntimeKind) throws -> PinnedLicense? {
        switch kind {
        case .composer:
            try pin(
                "https://raw.githubusercontent.com/composer/composer/2.10.3/LICENSE",
                "7855ac293067aebe7e51afdd23b9dea54b8be24187dbecc9b9142581c37f596c")
        case .rustfs:
            try pin(
                "https://raw.githubusercontent.com/rustfs/rustfs/d47f54bfb2f39f48bd1adda334bd27e151fe85b8/LICENSE",
                "3a9df97065824982b722fc7fac418a73ffd88febe968a3b9874423791581197a")
        case .cloudflared:
            try pin(
                "https://raw.githubusercontent.com/cloudflare/cloudflared/2026.9.3/LICENSE",
                "58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd")
        default: nil
        }
    }

    /// Downloads the license to `destination` and checks its digest. A changed text leaves no file.
    /// - Throws: `.invalid` when the text is not the reviewed one.
    public func fetch(to destination: URL, using fetcher: any HTTPFetching) async throws {
        let data = try await fetcher.data(from: url, limit: Self.sizeLimit)
        guard FileDigest.hexSHA256(of: data) == sha256 else {
            throw JerdError.invalid("The license file at \(url.absoluteString) changed. Jerd did not install it.")
        }
        try AtomicFile.write(data, to: destination, durability: .standard)
    }

    private static func pin(_ address: String, _ sha256: String) throws -> PinnedLicense {
        PinnedLicense(url: try .runtime(address), sha256: sha256)
    }
}
