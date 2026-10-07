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

    /// Prepares every pin of `group` in preparation order. Composer and the Laravel installer run with
    /// the PHP CLI (and `composer.phar`) that this run prepared before them.
    func prepare(_ group: PayloadGroup, catalog: RuntimePinCatalog, lzma: SupportLibrary?) async throws {
        let preparer = preparer
        for pin in Self.preparationOrder(catalog.pins(in: group)) {
            let existed = FileProbe.presence(at: try preparer.folder(for: pin)).mayExist
            var tools = PreparationTools()
            if !existed {
                context.console.detail("Preparing \(pin.id)…")
                tools = try Self.tools(for: pin, preparer: preparer, catalog: catalog, lzma: lzma)
            }
            let receipt = try await prepareReportingProgress(pin, preparer: preparer, catalog: catalog, tools: tools)
            if existed, let signature = pin.signature { await cacheSignature(signature, of: pin) }
            let verb = existed ? "Verified the prepared" : "Prepared"
            context.console.success("\(verb) \(pin.id): \(pin.kind.rawValue) \(receipt.version).")
        }
        try preparer.writeCatalog()
    }

    /// An earlier run may predate the signature cache, and the on-demand integration test needs the
    /// reviewed file. A cached file is used without the network. Otherwise one small download is
    /// tried; offline, the verified payload stays valid and a warning names the next step.
    func cacheSignature(_ signature: PinnedFile, of pin: RuntimePin) async {
        let cached = context.repository.runtimeDownloads.appending(path: signature.sha256)
        if (try? DownloadCache.isValid(cached, digest: signature.sha256)) == true { return }
        do {
            _ = try await fetcher.data(from: signature.url, limit: Int(signature.sizeLimit))
        } catch {
            context.console.warning(
                "\(pin.id): the signature file is not cached, and it cannot be downloaded now. The on-demand "
                    + "integration test needs it: run ./dev runtimes prepare database once with a network connection.")
        }
    }

    /// The pins in an order where each pin comes after the pins whose tools it needs: PHP, then Composer,
    /// then the rest in catalog order. The sort is stable, so the catalog order decides everything else.
    static func preparationOrder(_ pins: [RuntimePin]) -> [RuntimePin] {
        func rank(_ kind: RuntimeKind) -> Int {
            switch kind {
            case .php: 0
            case .composer: 1
            default: 2
            }
        }
        return pins.enumerated().sorted { (rank($0.element.kind), $0.offset) < (rank($1.element.kind), $1.offset) }
            .map(\.element)
    }

    /// The tools that a new preparation of `pin` needs from the payloads that this run prepared before it.
    static func tools(
        for pin: RuntimePin, preparer: PinnedPayloadPreparer, catalog: RuntimePinCatalog, lzma: SupportLibrary?
    ) throws -> PreparationTools {
        do {
            switch pin.kind {
            case .composer: return PreparationTools(phpCLI: try preparer.preparedExecutable(.php, catalog: catalog))
            case .laravel: return try preparer.developmentTools(catalog: catalog, lzma: lzma)
            case .rustfs: return PreparationTools(lzma: lzma)
            default: return PreparationTools()
            }
        } catch let error as JerdError {
            throw DevFailure.checkFailed("\(pin.id): \(error.message)")
        }
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
