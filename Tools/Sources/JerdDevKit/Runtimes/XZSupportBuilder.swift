import Foundation
import JerdArchive
import JerdFoundation
import JerdManifest
import JerdRuntimes

/// Builds the reviewed XZ library from its pinned source into `.build/runtimes/support/xz`, or
/// reuses an earlier build with the same pin, deployment target, and file digests.
///
/// The RustFS preparation copies the library into the storage payload (`LZMALinker`). The build
/// happens in a staging folder; one rename publishes it, so a failed build leaves no partial library.
struct XZSupportBuilder: Sendable {
    let folder: URL
    let source: PinnedSupportSource
    let deploymentTarget: String
    let fetcher: any HTTPFetching
    let context: DevContext

    /// The library and its license, ready for `PreparationTools.lzma`.
    func build() async throws -> SupportLibrary {
        let library = SupportLibrary(
            library: folder.appending(path: XZBuildPlan.libraryName),
            license: folder.appending(path: XZBuildPlan.licenseName))
        if try isReusable() {
            context.console.success("Verified the earlier build of XZ \(source.version).")
            return library
        }
        if FileProbe.presence(at: folder).mayExist {
            context.console.detail("The earlier XZ build is for another pin or changed. Building it again.")
            try FileManager.default.removeItem(at: folder)
        }
        let parent = folder.deletingLastPathComponent()
        try OwnedDirectory.create(parent)
        let staging = parent.appending(path: ".xz-staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        try OwnedDirectory.create(staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        let output = try await buildOutput(in: staging)
        try FileManager.default.moveItem(at: output, to: folder)
        context.console.success("Built and recorded XZ \(source.version).")
        return library
    }

    func isReusable() throws -> Bool {
        let receipt: SupportReceipt?
        do {
            receipt = try SupportReceipt.read(from: folder)
        } catch {
            return false
        }
        guard let receipt, receipt.matches(source, deploymentTarget: deploymentTarget) else { return false }
        do {
            try receipt.verify(in: folder)
            return true
        } catch {
            return false
        }
    }

    private func buildOutput(in staging: URL) async throws -> URL {
        let archive = staging.appending(path: "xz.tar.gz")
        context.console.detail("Downloading XZ \(source.version)…")
        let bytes = try await fetcher.download(
            from: source.archive.url, to: archive, limit: source.archive.size, progress: { _ in })
        guard bytes == source.archive.size, try FileDigest.hexSHA256(of: archive) == source.archive.sha256 else {
            throw DevFailure.checkFailed("The XZ \(source.version) download does not match its pin.")
        }
        let sourceFolder = staging.appending(path: "source", directoryHint: .isDirectory)
        try ArchiveExtractor.extract(
            archive, to: sourceFolder, policy: ExtractionPolicy(stripsRoot: true, outputLimit: 200_000_000))
        let plan = XZBuildPlan(
            source: sourceFolder, install: staging.appending(path: "install"), deploymentTarget: deploymentTarget,
            processors: ProcessInfo.processInfo.activeProcessorCount, inherited: context.environment)
        context.console.detail("Building XZ \(source.version) with the Xcode compiler…")
        for step in plan.buildSteps {
            try await run(step)
        }
        return try await collect(plan, into: staging.appending(path: "xz", directoryHint: .isDirectory))
    }

    /// Copies the library and its license, fixes the install name, signs ad hoc, and writes the receipt.
    private func collect(_ plan: XZBuildPlan, into output: URL) async throws -> URL {
        try OwnedDirectory.create(output)
        let library = output.appending(path: XZBuildPlan.libraryName)
        let license = output.appending(path: XZBuildPlan.licenseName)
        try DownloadCache.copyPrivate(plan.builtLibrary, to: library)
        try DownloadCache.copyPrivate(plan.upstreamLicenseFile, to: license)
        for step in XZBuildPlan.finishingSteps(library: library) {
            try await run(step)
        }
        let receipt = SupportReceipt(
            name: "xz", version: source.version, archiveSHA256: source.archive.sha256,
            deploymentTarget: deploymentTarget,
            files: [
                XZBuildPlan.libraryName: try FileDigest.hexSHA256(of: library),
                XZBuildPlan.licenseName: try FileDigest.hexSHA256(of: license),
            ])
        try receipt.encoded().write(to: output.appending(path: SupportReceipt.fileName))
        return output
    }

    private func run(_ step: Invocation) async throws {
        let result = try await context.run(step, output: context.console.verbose ? .stream : .capture)
        guard result.succeeded else {
            FailureLog.report(result, name: "xz-build", showsTail: true, context: context)
            throw DevFailure.checkFailed("The XZ build \(result.failureSummary): \(step.commandLine)")
        }
    }
}
