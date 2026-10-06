import Foundation
import JerdFoundation
import JerdManifest
import JerdProcess

/// The one preparation pipeline of managed updates and of bundled payloads:
/// download → verify → prepare → probe → permissions → hashes.
///
/// The caller owns the staging folder and decides what receipt to write and where the payload goes.
public struct RuntimePipeline: Sendable {
    /// The largest detached signature file.
    public static let signatureLimit = 16_384

    let fetcher: any HTTPFetching
    private let commands: any CommandRunning
    private let policy: ReleasePolicy

    public init(fetcher: any HTTPFetching, commands: any CommandRunning, policy: ReleasePolicy = ReleasePolicy()) {
        self.fetcher = fetcher
        self.commands = commands
        self.policy = policy
    }

    /// Prepares `release` inside `staging/payload`.
    public func prepare(
        _ release: RuntimeRelease, tools: PreparationTools, staging: StagingFolder,
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> PreparedPayload {
        try policy.validate(release)
        let payload = try staging.folder("payload")
        let artifact = try await acquire(release, staging: staging, progress: progress)
        let context = PreparationContext(
            release: release, artifact: artifact?.file, payload: payload, staging: staging.url, tools: tools,
            commands: commands, fetcher: fetcher)
        try Task.checkCancellation()
        progress(RuntimeInstallProgress(Self.preparationMessage(release.kind)))
        try await RuntimePreparers.preparer(for: release.kind).prepare(context)
        let digest: String
        if let artifact {
            digest = artifact.sha256
        } else {
            digest = try await lockDigest(release, payload: payload)
        }
        progress(RuntimeInstallProgress("Checking the installed version…"))
        let outcome = try await VersionProber(context: context).probe()
        let files = try await Self.recordFiles(of: payload)
        return PreparedPayload(
            directory: payload, release: release, version: outcome.version, archiveSHA256: digest,
            executable: outcome.executable, secondaryExecutable: outcome.secondaryExecutable, files: files)
    }

    /// The last step of every preparation: no Finder metadata (RT-3), private modes (I13), then the
    /// hash of every file (I16).
    package static func recordFiles(of payload: URL) async throws -> [RelativePath: PayloadFileRecord] {
        try await BlockingWork.run {
            try FinderMetadata.remove(in: payload)
            try PayloadPermissions.apply(payload)
            return try PayloadScanner.scan(payload)
        }
    }

    static func preparationMessage(_ kind: RuntimeKind) -> String {
        switch kind {
        case .redis: "Building Redis with the local compiler…"
        case .laravel: "Installing Laravel dependencies…"
        default: "Preparing runtime files…"
        }
    }

    /// The SHA-256 of the resolved `composer.lock`. A pinned lock must keep its pinned digest.
    private func lockDigest(_ release: RuntimeRelease, payload: URL) async throws -> String {
        let lock = payload.appendingPathComponent("composer.lock")
        let digest = try await BlockingWork.run { try FileDigest.hexSHA256(of: lock) }
        if case .lockedComposerProject = release.artifact, digest != release.archiveSHA256 {
            throw JerdError.invalid("The Laravel installer lock file changed. Review it and pin it again.")
        }
        return digest
    }
}
