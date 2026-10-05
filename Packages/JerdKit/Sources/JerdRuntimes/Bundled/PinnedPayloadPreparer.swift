import Foundation
import JerdFoundation
import JerdManifest
import JerdProcess

/// Prepares the pinned payloads of the app bundle with the same pipeline as managed updates.
///
/// `./dev runtimes prepare` is a thin driver: it loads the catalog, calls `prepare` for each pin in
/// catalog order, and copies the catalog with `writeCatalog`. The output has the bundle layout:
/// `<output>/runtimes.json` and `<output>/<group>/<payload ID>/` with `payload-receipt.json`.
public struct PinnedPayloadPreparer: Sendable {
    /// The repository folder `Runtimes/`, which holds the catalog and the Laravel project.
    public let catalogDirectory: URL
    /// The staging folder of payloads, for example `.build/runtimes/payloads`.
    public let output: URL
    private let pipeline: RuntimePipeline

    public init(
        catalogDirectory: URL, output: URL, fetcher: any HTTPFetching, commands: any CommandRunning,
        platform: HostPlatform = .current
    ) {
        self.catalogDirectory = catalogDirectory
        self.output = output
        pipeline = RuntimePipeline(fetcher: fetcher, commands: commands, policy: ReleasePolicy(platform: platform))
    }

    /// The validated catalog of the repository.
    public func catalog() throws -> RuntimePinCatalog {
        try RuntimePinCatalog.decode(
            BundleFile.read(
                catalogDirectory.appendingPathComponent(RuntimePinCatalog.fileName), limit: RuntimePinCatalog.sizeLimit)
        )
    }

    /// The release that a pin names: the exact archive, its digest, and the MySQL signature.
    public func release(for pin: RuntimePin, architecture: CPUArchitecture) throws -> RuntimeRelease {
        let artifact: ReleaseArtifact
        if let archive = pin.archive {
            artifact = .archive(archive.url, size: .exact(archive.size))
        } else if let project = pin.composerProject {
            artifact = .lockedComposerProject(project.directory.url(in: catalogDirectory))
        } else {
            throw JerdError.invalid("The pin \(pin.id) names no artifact.")
        }
        return RuntimeRelease(
            kind: pin.kind, version: pin.version, artifact: artifact, archiveSHA256: pin.artifactSHA256,
            signatureURL: pin.signature?.url, releasePage: pin.releasePage, architecture: architecture)
    }

    /// The folder of a prepared pin.
    public func folder(for pin: RuntimePin) throws -> URL {
        guard let group = pin.group else { throw JerdError.invalid("The pin \(pin.id) is never bundled.") }
        return output.appendingPathComponent(group.rawValue).appendingPathComponent(pin.id, isDirectory: true)
    }

    /// Prepares one pin, or verifies and keeps an earlier preparation of the same pin.
    @discardableResult
    public func prepare(
        _ pin: RuntimePin, architecture: CPUArchitecture, tools: PreparationTools,
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void = { _ in }
    ) async throws -> PayloadReceipt {
        let target = try folder(for: pin)
        if FileProbe.presence(at: target).mayExist { return try verifiedExisting(pin, at: target) }
        try OwnedDirectory.create(target.deletingLastPathComponent())
        let staging = try StagingFolder(in: target.deletingLastPathComponent())
        defer { staging.remove() }
        let release = try release(for: pin, architecture: architecture)
        let prepared = try await pipeline.prepare(release, tools: tools, staging: staging, progress: progress)
        let receipt = prepared.payloadReceipt(id: pin.id)
        try AtomicFile.write(
            try receipt.encoded(), to: prepared.directory.appendingPathComponent(PayloadReceipt.fileName))
        try Task.checkCancellation()
        try FolderMove.withoutReplacing(prepared.directory, to: target)
        return receipt
    }

    /// The prepared PHP CLI and `composer.phar`, which the Laravel installer needs.
    public func developmentTools(catalog: RuntimePinCatalog, lzma: SupportLibrary? = nil) throws -> PreparationTools {
        func executable(_ kind: RuntimeKind) throws -> URL? {
            guard let pin = catalog.pin(for: kind) else { return nil }
            let folder = try folder(for: pin)
            let data = try AtomicFile.read(
                folder.appendingPathComponent(PayloadReceipt.fileName), limit: PayloadReceipt.sizeLimit)
            return try PayloadReceipt.decode(data).executable.url(in: folder)
        }
        return PreparationTools(phpCLI: try executable(.php), composer: try executable(.composer), lzma: lzma)
    }

    /// Copies the catalog bytes into the output, as the bundle needs them.
    public func writeCatalog() throws {
        let name = RuntimePinCatalog.fileName
        let data = try BundleFile.read(
            catalogDirectory.appendingPathComponent(name), limit: RuntimePinCatalog.sizeLimit)
        _ = try RuntimePinCatalog.decode(data)
        try OwnedDirectory.create(output)
        try AtomicFile.write(data, to: output.appendingPathComponent(name))
    }

    private func verifiedExisting(_ pin: RuntimePin, at folder: URL) throws -> PayloadReceipt {
        let data = try AtomicFile.read(
            folder.appendingPathComponent(PayloadReceipt.fileName), limit: PayloadReceipt.sizeLimit)
        let receipt = try PayloadReceipt.decode(data)
        guard receipt.id == pin.id, receipt.kind == pin.kind, receipt.releaseVersion == pin.version,
            receipt.archiveSHA256 == pin.artifactSHA256
        else { throw JerdError.invalid("The prepared payload \(pin.id) uses another pin. It was preserved.") }
        try VerifiedPayloadInstaller.verify(folder, receipt: receipt)
        return receipt
    }
}
