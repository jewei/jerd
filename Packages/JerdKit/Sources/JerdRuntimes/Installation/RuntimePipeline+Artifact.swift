import Foundation
import JerdFoundation
import JerdManifest

extension RuntimePipeline {
    /// A downloaded and verified artifact.
    struct VerifiedArtifact {
        let file: URL
        let sha256: String
    }

    /// Downloads and verifies an archive. Composer resolutions have no artifact.
    func acquire(
        _ release: RuntimeRelease, staging: StagingFolder,
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> VerifiedArtifact? {
        guard case .archive(let url, let size) = release.artifact else { return nil }
        progress(RuntimeInstallProgress(Self.downloadMessage(release.title, fraction: 0, size: size), 0))
        let file = staging.url.appendingPathComponent("download")
        let count = try await fetcher.download(from: url, to: file, limit: size.limit) { fraction in
            progress(
                RuntimeInstallProgress(Self.downloadMessage(release.title, fraction: fraction, size: size), fraction))
        }
        if case .exact(let expected) = size, count != expected {
            throw JerdError.invalid("The download does not have the size that its publisher states.")
        }
        progress(RuntimeInstallProgress("Verifying download…"))
        let sha256 = try await BlockingWork.run { try FileDigest.hexSHA256(of: file) }
        if let expected = release.archiveSHA256, sha256 != expected {
            throw JerdError.invalid(
                "The \(release.title) download does not match its expected SHA-256. Jerd installed nothing.")
        }
        if let signatureURL = release.signatureURL {
            try await verifySignature(of: file, at: signatureURL, release: release)
        }
        return VerifiedArtifact(file: file, sha256: sha256)
    }

    /// `Downloading MySQL 8.4.11… 70.6 MB of 168 MB`: the bytes so far of an exact size. Without an
    /// exact size, or before the first byte, only the title.
    package static func downloadMessage(_ title: String, fraction: Double, size: ByteLimit) -> String {
        guard case .exact(let total) = size, fraction > 0 else { return "Downloading \(title)…" }
        let received = Int64((Double(total) * min(1, fraction)).rounded())
        return "Downloading \(title)… \(ByteText.format(received)) of \(ByteText.format(total))"
    }

    /// Checks the detached publisher signature with the pinned key of the kind. A pinned release
    /// also needs exactly its reviewed signature file: its URL, size limit, and SHA-256.
    private func verifySignature(of file: URL, at url: URL, release: RuntimeRelease) async throws {
        let kind = release.kind
        guard let key = Self.publisherKey(for: kind) else {
            throw JerdError.invalid("The runtime download has no verification method.")
        }
        let pin = release.pinnedSignature
        let mismatch = JerdError.invalid("The \(kind.title) signature file does not match its reviewed pin.")
        if let pin, pin.url != url { throw mismatch }
        let limit = pin.map { Int($0.sizeLimit) } ?? Self.signatureLimit
        let signature = try await fetcher.data(from: url, limit: limit)
        if let pin, FileDigest.hexSHA256(of: signature) != pin.sha256 { throw mismatch }
        try await BlockingWork.run {
            try PinnedRSAVerifier(key: key).verify(file: file, armoredSignature: signature)
        }
    }

    /// The pinned publisher key of a kind whose archives carry an OpenPGP signature.
    static func publisherKey(for kind: RuntimeKind) -> PinnedRSAKey? {
        kind == .mysql ? .mysqlRelease2025 : nil
    }
}
