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
        let message = "Downloading \(release.kind.title) \(release.version)…"
        progress(RuntimeInstallProgress(message, 0))
        let file = staging.url.appendingPathComponent("download")
        let count = try await fetcher.download(from: url, to: file, limit: size.limit) { fraction in
            progress(RuntimeInstallProgress(message, fraction))
        }
        if case .exact(let expected) = size, count != expected {
            throw JerdError.invalid("The download does not have the size that its publisher states.")
        }
        progress(RuntimeInstallProgress("Verifying download…"))
        let sha256 = try await BlockingWork.run { try FileDigest.hexSHA256(of: file) }
        if let expected = release.archiveSHA256, sha256 != expected {
            throw JerdError.invalid("The runtime download failed its SHA-256 check.")
        }
        if let signatureURL = release.signatureURL {
            try await verifySignature(of: file, at: signatureURL, kind: release.kind, staging: staging)
        }
        return VerifiedArtifact(file: file, sha256: sha256)
    }

    /// Checks the detached publisher signature with the pinned key of the kind.
    private func verifySignature(of file: URL, at url: URL, kind: RuntimeKind, staging: StagingFolder) async throws {
        guard let key = Self.publisherKey(for: kind) else {
            throw JerdError.invalid("The runtime download has no verification method.")
        }
        let signature = try await fetcher.data(from: url, limit: Self.signatureLimit)
        try await BlockingWork.run {
            try PinnedRSAVerifier(key: key).verify(file: file, armoredSignature: signature)
        }
    }

    /// The pinned publisher key of a kind whose archives carry an OpenPGP signature.
    static func publisherKey(for kind: RuntimeKind) -> PinnedRSAKey? {
        kind == .mysql ? .mysqlRelease2025 : nil
    }
}
