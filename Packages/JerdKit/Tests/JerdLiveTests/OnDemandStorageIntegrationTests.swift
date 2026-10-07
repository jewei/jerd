import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import JerdStorage
import JerdTestSupport
import Testing

@testable import JerdLive

/// Opt-in: installs the on-demand RustFS through the app wiring (`LiveDomain`, its one
/// `RuntimeInstaller`, the live Storage port, the real fetcher, and the real preparer with the XZ
/// library of the app bundle) into a temporary data root, then starts storage, creates a bucket,
/// and stops. The download comes from a local file server inside URLSession: no internet.
///
/// `JERD_ON_DEMAND_STORAGE_INTEGRATION=1`, `JERD_RUNTIME_DOWNLOADS=<folder of files named by SHA-256>`
/// (`.build/runtimes/downloads`), `JERD_XZ_SUPPORT=<prepared support/xz folder>`
/// (`.build/runtimes/support/xz`), and `JERD_STORAGE_RUNTIME` (the prepared RustFS payload, for
/// its pinned license). `./dev test --integration storage` sets all four.
@Suite(
    "On-demand RustFS integration", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["JERD_ON_DEMAND_STORAGE_INTEGRATION"] == "1"))
struct OnDemandStorageIntegrationTests {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// A bundle with the committed catalog and the XZ support folder, as a release app has them.
    private func bundle(in folder: TemporaryDirectory) throws -> URL {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../Runtimes/runtimes.json").standardizedFileURL
        let payloads = "Jerd.app/Contents/Resources/RuntimePayloads"
        _ = try folder.file("\(payloads)/runtimes.json", Data(contentsOf: repository))
        let xz = URL(fileURLWithPath: try #require(environment["JERD_XZ_SUPPORT"], "Set JERD_XZ_SUPPORT."))
        let target = BundledSupportLibrary.folder("xz", in: folder.path(payloads))
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: xz, to: target)
        return folder.path("Jerd.app/Contents/Resources")
    }

    /// Serves the pinned archive from the downloads folder, and the pinned license (the archive has
    /// none) from the prepared RustFS payload, which holds the same reviewed text.
    private func serve(_ release: RuntimeRelease) throws {
        let downloads = try #require(environment["JERD_RUNTIME_DOWNLOADS"], "Set JERD_RUNTIME_DOWNLOADS.")
        let url = try #require(release.artifact.downloadURL)
        LocalDownloadProtocol.serve(
            url,
            from: URL(fileURLWithPath: downloads, isDirectory: true).appendingPathComponent(
                try #require(release.archiveSHA256)))
        let payload = try #require(environment["JERD_STORAGE_RUNTIME"], "Set JERD_STORAGE_RUNTIME.")
        let license = URL(fileURLWithPath: payload).appendingPathComponent("LICENSE")
        let pinned = try #require(try PinnedLicense.of(.rustfs))
        try #require(
            try FileDigest.hexSHA256(of: license) == pinned.sha256, "The prepared license is not the pinned one.")
        LocalDownloadProtocol.serve(pinned.url, from: license)
    }

    private func fetcher() -> URLSessionFetcher {
        URLSessionFetcher(userAgent: "Jerd/test runtime-updates") {
            let configuration = URLSessionFetcher.ephemeralConfiguration()
            configuration.protocolClasses = [LocalDownloadProtocol.self]
            return configuration
        }
    }

    @Test("Installs the pinned RustFS with the app's XZ library, then runs storage with a bucket")
    func installsAndRunsRustFS() async throws {
        let folder = try TemporaryDirectory("on-demand-storage")
        defer { folder.remove() }
        let configuration = LiveConfiguration(
            layout: folder.layout, appBundle: folder.path("Jerd.app"), resources: try bundle(in: folder),
            appVersion: "test")
        let domain = LiveDomain(configuration: configuration, fetcher: fetcher())
        let release = try #require(try domain.onDemandRuntimes.release(for: .rustfs))
        try serve(release)
        let port = LiveStoragePort(domain: domain)
        let before = LocalDownloadProtocol.requests(for: release)

        // The launch downloads nothing and installs nothing: RustFS is not embedded.
        #expect(try await port.load().settings.runtime == nil)
        #expect(await port.runtimeSetupFailure() == nil)
        #expect(LocalDownloadProtocol.requests(for: release) == before)
        let offer = try #require(await port.runtimeOffer())
        #expect(offer.title == "RustFS 1.0.0" && !offer.reusesInstalledCopy)

        let messages = ProgressLog()
        let runtime = try await port.installRuntime { messages.append($0.message) }
        #expect(messages.all.contains { $0.hasPrefix("Downloading RustFS 1.0.0… ") && $0.contains(" of ") })
        let directory = URL(fileURLWithPath: runtime.path)
        #expect(runtime.path.hasPrefix(folder.layout.runtimes.managedRuntimesDirectory.path))
        // The installed runtime keeps the library that it loads at run time, and no Homebrew path.
        #expect(FileProbe.presence(at: directory.appendingPathComponent("liblzma.5.dylib")) == .present)
        let binary = try Data(contentsOf: directory.appendingPathComponent("rustfs"))
        let libraries = try MachOLoadCommands.libraries(in: binary).map(\.name)
        #expect(libraries.contains("@loader_path/liblzma.5.dylib"))
        #expect(!libraries.contains { $0.hasPrefix("/opt/homebrew") })
        #expect(await port.snapshot().settings.runtime == runtime)
        // A second install would reuse the build: nothing would be downloaded.
        #expect(await port.runtimeOffer()?.reusesInstalledCopy == true)

        do {
            try await port.addBucket(name: "on-demand", publicRead: false)
            #expect(await port.snapshot().state.isRunning)
            #expect(await port.snapshot().settings.bucket("on-demand")?.setupComplete == true)
            try await port.stop()
        } catch {
            try? await port.stop()
            throw error
        }
        #expect(await port.snapshot().state == .stopped)
        // Stop keeps the bucket and the credentials.
        #expect(await port.snapshot().settings.bucket("on-demand") != nil)
        #expect(try await port.credentials().accessKey.isEmpty == false)
    }
}
