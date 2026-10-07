import Foundation
import JerdDatabases
import JerdFoundation
import JerdManifest
import JerdRuntimes
import JerdServiceKit
import JerdTestSupport
import Testing

@testable import JerdLive

/// Opt-in: installs one pinned database engine through the app pipeline (the live Databases port,
/// `RuntimeInstaller`, the real fetcher and preparers) into a temporary data root, then creates,
/// starts, and stops a service with it. The downloads come from a local file server inside
/// URLSession, so the test needs no internet.
///
/// `JERD_ON_DEMAND_INTEGRATION=1`, `JERD_RUNTIME_DOWNLOADS=<folder of files named by SHA-256>` (for
/// example `.build/runtimes/downloads`), and optionally `JERD_ON_DEMAND_ENGINE` (`postgresql` by
/// default; `mysql` also needs its signature file in the folder).
@Suite(
    "On-demand database runtime integration", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["JERD_ON_DEMAND_INTEGRATION"] == "1"))
struct OnDemandRuntimeIntegrationTests {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    private var engine: DatabaseEngine {
        DatabaseEngine(rawValue: environment["JERD_ON_DEMAND_ENGINE"] ?? "postgresql") ?? .postgresql
    }

    /// A bundle with only the committed catalog, as in an app without database payloads.
    private func bundle(in folder: TemporaryDirectory) throws -> URL {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../Runtimes/runtimes.json").standardizedFileURL
        _ = try folder.file("Jerd.app/Contents/Resources/RuntimePayloads/runtimes.json", Data(contentsOf: repository))
        return folder.path("Jerd.app/Contents/Resources")
    }

    /// Serves the pinned archive (and the MySQL signature) from the downloads folder.
    private func serve(_ release: RuntimeRelease) throws {
        let downloads = try #require(environment["JERD_RUNTIME_DOWNLOADS"], "Set JERD_RUNTIME_DOWNLOADS.")
        let folder = URL(fileURLWithPath: downloads, isDirectory: true)
        let url = try #require(release.artifact.downloadURL)
        LocalDownloadProtocol.serve(url, from: folder.appendingPathComponent(try #require(release.archiveSHA256)))
        if let signature = release.pinnedSignature {
            LocalDownloadProtocol.serve(signature.url, from: folder.appendingPathComponent(signature.sha256))
        }
    }

    private func fetcher() -> URLSessionFetcher {
        URLSessionFetcher(userAgent: "Jerd/test runtime-updates") {
            let configuration = URLSessionFetcher.ephemeralConfiguration()
            configuration.protocolClasses = [LocalDownloadProtocol.self]
            return configuration
        }
    }

    @Test("Installs the pinned engine, registers it, and runs a service with it")
    func installsAndRunsAPinnedEngine() async throws {
        let folder = try TemporaryDirectory("on-demand")
        defer { folder.remove() }
        let configuration = LiveConfiguration(
            layout: folder.layout, appBundle: folder.path("Jerd.app"), resources: try bundle(in: folder),
            appVersion: "test")
        let domain = LiveDomain(configuration: configuration)
        let release = try #require(try domain.onDemandRuntimes.releases().first { $0.kind.rawValue == engine.rawValue })
        try serve(release)
        let installer = RuntimeInstaller(
            directory: folder.layout.runtimes.managedRuntimesDirectory, fetcher: fetcher())
        let port = LiveDatabasesPort(
            manager: domain.databases, runtimes: BundledServiceRuntimes(bootstrap: domain.bootstrap),
            layout: folder.layout.databases,
            onDemand: DatabaseRuntimeInstaller(
                releases: domain.onDemandRuntimes, installer: installer, manager: domain.databases))

        // The launch downloads nothing. The test bundle holds only the catalog, so the setup of the
        // embedded Redis finds no payload and installs nothing; it never falls back to a download.
        #expect(try await port.load().configuration.runtimes.isEmpty)
        #expect(LocalDownloadProtocol.requests.isEmpty)
        #expect(await port.runtimeOffers().map(\.engine) == [.mysql, .postgresql])
        #expect(await port.runtimeOffers().first { $0.engine == .postgresql }?.versionLabel == "18.6")

        let runtime = try await port.installRuntime(engine) { _ in }
        #expect(
            runtime.engine == engine && runtime.path.hasPrefix(folder.layout.runtimes.managedRuntimesDirectory.path))
        let receipt = try BuildReceipt.decode(
            Data(contentsOf: URL(fileURLWithPath: runtime.path).appendingPathComponent(BuildReceipt.fileName)))
        #expect(receipt.archiveSHA256 == release.archiveSHA256 && receipt.releaseVersion == release.version)
        #expect(await port.snapshot().configuration.runtimes == [runtime])

        // A second install of the same pin uses the verified build without a download.
        let requests = LocalDownloadProtocol.requests.count
        #expect(try await installer.install(release).folderName == runtime.id)
        #expect(LocalDownloadProtocol.requests.count == requests)

        let service = try await port.add(
            name: "On demand", runtimeID: runtime.id, port: try await port.suggestedPort(for: engine))
        do {
            try await port.start(service.id)
            #expect(await port.snapshot().state(of: service.id).isRunning)
            try await port.stop(service.id)
        } catch {
            // Stop what started before the folder goes; the stop is graceful only.
            try? await port.stopAll()
            throw error
        }
        #expect(await port.snapshot().state(of: service.id) == .stopped)
    }
}
