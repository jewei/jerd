import Darwin
import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes

/// An `HTTPFetching` that keeps every pinned download in `.build/runtimes/downloads/<sha256>`.
///
/// Only a URL with a pinned SHA-256 is cached, and only a file with exactly that digest enters or
/// leaves the cache. A cached file with another digest is removed and downloaded again. The pipeline
/// still checks size and digest of every file that this type returns, so the cache cannot weaken a
/// check. Other requests pass through unchanged.
struct DownloadCache: HTTPFetching {
    let folder: URL
    let upstream: any HTTPFetching
    /// The pinned SHA-256 of each cacheable URL.
    let digests: [URL: String]

    /// The archive digests of every pin and support source of `catalog`.
    static func digests(of catalog: RuntimePinCatalog) -> [URL: String] {
        var digests: [URL: String] = [:]
        for archive in catalog.pins.compactMap(\.archive) + catalog.supportSources.values.map(\.archive) {
            digests[archive.url] = archive.sha256
        }
        return digests
    }

    func data(from url: URL, limit: Int) async throws -> Data {
        try await upstream.data(from: url, limit: limit)
    }

    func download(
        from url: URL, to destination: URL, limit: Int64, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Int64 {
        guard let digest = digests[url] else {
            return try await upstream.download(from: url, to: destination, limit: limit, progress: progress)
        }
        let cached = folder.appending(path: digest)
        if try Self.isValid(cached, digest: digest) {
            try Self.copyPrivate(cached, to: destination)
            progress(1)
            return try Self.size(of: destination)
        }
        let bytes = try await upstream.download(from: url, to: destination, limit: limit, progress: progress)
        if try FileDigest.hexSHA256(of: destination) == digest {
            try store(destination, as: cached)
        }
        return bytes
    }

    /// True for a cached regular file with the digest; a file with another digest is removed.
    static func isValid(_ cached: URL, digest: String) throws -> Bool {
        guard FileProbe.presence(at: cached).mayExist else { return false }
        let matches: Bool
        do {
            matches = try FileDigest.hexSHA256(of: cached) == digest
        } catch {
            // A cached link, folder, or unreadable file is never used. It is build output, not user data.
            matches = false
        }
        if matches { return true }
        try FileManager.default.removeItem(at: cached)
        return false
    }

    /// Copies through a temporary name and renames, so that the cache never holds a partial file.
    private func store(_ file: URL, as cached: URL) throws {
        try OwnedDirectory.create(folder)
        let partial = folder.appending(path: ".\(cached.lastPathComponent).\(UUID().uuidString).part")
        try Self.copyPrivate(file, to: partial)
        guard rename(partial.path, cached.path) == 0 else {
            try? FileManager.default.removeItem(at: partial)
            throw DevFailure.checkFailed("Cannot store \(cached.path) (\(SystemError.describe(errno))).")
        }
    }

    static func copyPrivate(_ source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
        guard chmod(destination.path, 0o600) == 0 else {
            throw DevFailure.checkFailed("Cannot protect \(destination.path) (\(SystemError.describe(errno))).")
        }
    }

    static func size(of file: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}
