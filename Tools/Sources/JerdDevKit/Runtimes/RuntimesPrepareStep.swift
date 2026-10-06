import Foundation
import JerdFoundation
import JerdManifest
import JerdProcess
import JerdRuntimes

/// `./dev runtimes prepare`: a thin driver over `PinnedPayloadPreparer`, which uses the same pipeline
/// as managed runtime updates in the app. Each pin is prepared once; a later run verifies it.
struct RuntimesPrepareStep: Sendable {
    let context: DevContext
    let fetcher: any HTTPFetching
    let commands: any CommandRunning

    /// The live step: HTTPS downloads through the digest cache, and JerdKit's command runner.
    static func live(_ context: DevContext, catalog: RuntimePinCatalog) -> RuntimesPrepareStep {
        let cache = DownloadCache(
            folder: context.repository.runtimeDownloads, upstream: URLSessionFetcher(),
            digests: DownloadCache.digests(of: catalog))
        return RuntimesPrepareStep(context: context, fetcher: cache, commands: CommandRunner())
    }

    var preparer: PinnedPayloadPreparer {
        PinnedPayloadPreparer(
            catalogDirectory: context.repository.runtimeSources, output: context.repository.payloads,
            fetcher: fetcher, commands: commands)
    }

    /// The XZ library, when selected.
    func prepareXZ(catalog: RuntimePinCatalog) async throws -> SupportLibrary {
        guard let source = catalog.supportSources["xz"] else {
            throw DevFailure.checkFailed("The runtime pin catalog has no XZ support source.")
        }
        let base = XcconfigFile(
            path: "Configuration/Base.xcconfig",
            text: try RepositoryPolicy.readText("Configuration/Base.xcconfig", in: context.repository))
        let builder = XZSupportBuilder(
            folder: context.repository.runtimeSupport.appending(path: "xz", directoryHint: .isDirectory),
            source: source, deploymentTarget: try base.value(of: "MACOSX_DEPLOYMENT_TARGET"), fetcher: fetcher,
            context: context)
        return try await builder.build()
    }

    /// Prepares every pin of `group` in catalog order. The Laravel installer needs the PHP and Composer
    /// payloads of the same group, which come first in the catalog.
    func prepare(_ group: PayloadGroup, catalog: RuntimePinCatalog, lzma: SupportLibrary?) async throws {
        let preparer = preparer
        for pin in catalog.pins(in: group) {
            let tools: PreparationTools
            switch pin.kind {
            case .laravel: tools = try preparer.developmentTools(catalog: catalog, lzma: lzma)
            case .rustfs: tools = PreparationTools(lzma: lzma)
            default: tools = PreparationTools()
            }
            let existed = FileProbe.presence(at: try preparer.folder(for: pin)).mayExist
            if !existed {
                context.console.detail("Preparing \(pin.id)…")
            }
            let receipt = try await prepareReportingProgress(pin, preparer: preparer, catalog: catalog, tools: tools)
            let verb = existed ? "Verified the prepared" : "Prepared"
            context.console.success("\(verb) \(pin.id): \(pin.kind.rawValue) \(receipt.version).")
        }
        try preparer.writeCatalog()
    }

    private func prepareReportingProgress(
        _ pin: RuntimePin, preparer: PinnedPayloadPreparer, catalog: RuntimePinCatalog, tools: PreparationTools
    ) async throws -> PayloadReceipt {
        let console = context.console
        let messages = ProgressMessages()
        do {
            return try await preparer.prepare(pin, architecture: catalog.architecture, tools: tools) { progress in
                if messages.isNew(progress.message) { console.detail(progress.message) }
            }
        } catch let error as JerdError {
            throw DevFailure.checkFailed("\(pin.id): \(error.message)\(Self.hint(for: error))")
        }
    }

    /// A next step for the errors that a user can fix here.
    static func hint(for error: JerdError) -> String {
        error.message.contains("uses another pin")
            ? " Remove .build/runtimes/payloads, or run ./dev clean --all, and prepare again." : ""
    }

    /// The host must match the catalog architecture, and Redis and XZ need the Xcode compiler.
    func checkPrerequisites(catalog: RuntimePinCatalog, selection: RuntimeSelection) async throws {
        guard HostPlatform.current.architecture == catalog.architecture else {
            throw DevFailure.missingPrerequisite(
                "The pinned runtimes are for \(catalog.architecture.rawValue) Macs. Prepare them on such a Mac.")
        }
        guard selection.buildsXZ || selection.groups.contains(.database) else { return }
        let find = Invocation(
            executable: context.toolchain.xcrun, arguments: ["--find", "clang"], timeout: TimeLimit.probe)
        guard try await context.run(find, output: .capture).succeeded else {
            throw DevFailure.missingPrerequisite(
                "The Redis and XZ builds need the Xcode compiler. Install Xcode, then run "
                    + "sudo xcode-select --switch /Applications/Xcode.app.")
        }
    }
}
