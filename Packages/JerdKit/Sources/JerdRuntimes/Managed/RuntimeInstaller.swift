import Darwin
import Foundation
import JerdFoundation
import JerdManifest
import JerdProcess

/// Installs managed runtime builds into `runtime-updates/`. Activation is a separate step.
///
/// One installation runs at a time. A build is prepared in a private staging folder, gets its
/// `update-receipt.json`, and moves into its final folder with one rename that never replaces an
/// existing folder. Cancellation is honored until that rename.
public actor RuntimeInstaller {
    public nonisolated let store: ManagedRuntimeStore
    private let pipeline: RuntimePipeline
    private var isInstalling = false

    public init(
        directory: URL, fetcher: any HTTPFetching, commands: any CommandRunning = CommandRunner(),
        policy: ReleasePolicy = ReleasePolicy()
    ) {
        store = ManagedRuntimeStore(directory: directory, architecture: policy.platform.architecture)
        pipeline = RuntimePipeline(fetcher: fetcher, commands: commands, policy: policy)
    }

    /// The installed builds, each folder on its own.
    public func list() async -> [ManagedRuntimeListing] {
        let store = store
        return (try? await BlockingWork.run { store.list() }) ?? []
    }

    /// Removes staging folders that a crash left behind. Does nothing while an installation runs.
    @discardableResult
    public func removeAbandonedStaging() -> [String] {
        guard !isInstalling else { return [] }
        return StagingFolder.removeAbandoned(in: store.directory)
    }

    /// Installs `release`, or returns its verified build when it is already installed.
    /// - Throws: `.unavailable` while another installation runs; any step error; `CancellationError`.
    public func install(
        _ release: RuntimeRelease, tools: PreparationTools = PreparationTools(),
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void = { _ in }
    ) async throws -> ManagedRuntime {
        guard !isInstalling else { throw JerdError.unavailable("Wait for the current runtime installation to finish.") }
        isInstalling = true
        defer { isInstalling = false }
        let store = store
        try OwnedDirectory.create(store.directory)
        if let installed = try await BlockingWork.run({ try store.existing(release) }) { return installed }
        let staging = try StagingFolder(in: store.directory)
        defer { staging.remove() }
        let runtime: ManagedRuntime
        do {
            let prepared = try await pipeline.prepare(release, tools: tools, staging: staging, progress: progress)
            // The last point where cancellation stops the installation: the rename below is final.
            try Task.checkCancellation()
            runtime = try await BlockingWork.run { try Self.commit(prepared, store: store) }
        } catch  where DiskSpace.isOutOfSpace(error) {
            throw DiskSpace.outOfSpace
        }
        progress(RuntimeInstallProgress("Installed \(release.kind.title) \(runtime.version).", 1))
        return runtime
    }

    /// Writes the receipt and renames the payload into its final folder (I7, I13, I20).
    private static func commit(_ prepared: PreparedPayload, store: ManagedRuntimeStore) throws -> ManagedRuntime {
        let release = prepared.release
        if let existing = try store.existingBuild(
            kind: release.kind, releaseVersion: release.version, archiveSHA256: prepared.archiveSHA256)
        {
            return existing
        }
        let receipt = prepared.buildReceipt()
        try AtomicFile.write(receipt.encoded(), to: prepared.directory.appendingPathComponent(BuildReceipt.fileName))
        let target = store.directory.appendingPathComponent(
            BuildReceipt.folderName(
                kind: release.kind, releaseVersion: release.version, architecture: store.architecture,
                archiveSHA256: prepared.archiveSHA256), isDirectory: true)
        try FolderMove.withoutReplacing(prepared.directory, to: target)
        return ManagedRuntime(receipt: receipt, directory: target)
    }
}
