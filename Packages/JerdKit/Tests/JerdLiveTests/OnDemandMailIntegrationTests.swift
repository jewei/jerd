import Foundation
import JerdFoundation
import JerdMail
import JerdManifest
import JerdRuntimes
import JerdTestSupport
import Testing

@testable import JerdLive

/// Opt-in: installs the on-demand Mailpit through the app wiring (`LiveDomain`, its one
/// `RuntimeInstaller`, the live Mail port, the real fetcher, and the real preparer) into a
/// temporary data root, then starts mail, sends a test email, and stops. The download comes from a
/// local file server inside URLSession: no internet.
///
/// `JERD_ON_DEMAND_MAIL_INTEGRATION=1` and `JERD_RUNTIME_DOWNLOADS=<folder of files named by
/// SHA-256>` (`.build/runtimes/downloads`). `./dev test --integration mail` sets both.
@Suite(
    "On-demand Mailpit integration", .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["JERD_ON_DEMAND_MAIL_INTEGRATION"] == "1"))
struct OnDemandMailIntegrationTests {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    /// A bundle with only the committed catalog, as a release app without Mailpit has it.
    private func bundle(in folder: TemporaryDirectory) throws -> URL {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../Runtimes/runtimes.json").standardizedFileURL
        _ = try folder.file("Jerd.app/Contents/Resources/RuntimePayloads/runtimes.json", Data(contentsOf: repository))
        return folder.path("Jerd.app/Contents/Resources")
    }

    /// Serves the pinned archive from the downloads folder. The archive holds its own license.
    private func serve(_ release: RuntimeRelease) throws {
        let downloads = try #require(environment["JERD_RUNTIME_DOWNLOADS"], "Set JERD_RUNTIME_DOWNLOADS.")
        let url = try #require(release.artifact.downloadURL)
        LocalDownloadProtocol.serve(
            url,
            from: URL(fileURLWithPath: downloads, isDirectory: true).appendingPathComponent(
                try #require(release.archiveSHA256)))
    }

    private func fetcher() -> URLSessionFetcher {
        URLSessionFetcher(userAgent: "Jerd/test runtime-updates") {
            let configuration = URLSessionFetcher.ephemeralConfiguration()
            configuration.protocolClasses = [LocalDownloadProtocol.self]
            return configuration
        }
    }

    @Test("Installs the pinned Mailpit, then runs mail, captures a test email, and keeps it after Stop")
    func installsAndRunsMailpit() async throws {
        let folder = try TemporaryDirectory("on-demand-mail")
        defer { folder.remove() }
        let configuration = LiveConfiguration(
            layout: folder.layout, appBundle: folder.path("Jerd.app"), resources: try bundle(in: folder),
            appVersion: "test")
        let domain = LiveDomain(configuration: configuration, fetcher: fetcher())
        let release = try #require(try domain.onDemandRuntimes.release(for: .mailpit))
        try serve(release)
        let port = LiveMailPort(domain: domain)
        let before = LocalDownloadProtocol.requests(for: release)

        // The launch downloads nothing and installs nothing: Mailpit is not embedded.
        #expect(try await port.load().settings.runtime == nil)
        #expect(await port.runtimeSetupFailure() == nil)
        #expect(LocalDownloadProtocol.requests(for: release) == before)
        #expect(FileProbe.presence(at: folder.layout.runtimes.mailRuntimesDirectory) == .absent)
        let offer = try #require(await port.runtimeOffer())
        #expect(offer.title == "Mailpit 1.31.3" && !offer.reusesInstalledCopy)

        let messages = ProgressLog()
        let runtime = try await port.installRuntime { messages.append($0.message) }
        #expect(messages.all.contains { $0.hasPrefix("Downloading Mailpit 1.31.3… ") && $0.contains(" of ") })
        #expect(runtime.path.hasPrefix(folder.layout.runtimes.managedRuntimesDirectory.path))
        let settings = await port.snapshot().settings
        #expect(settings.runtime == runtime && settings.smtpPort != settings.webPort)
        // A second install would reuse the build: nothing would be downloaded.
        #expect(await port.runtimeOffer()?.reusesInstalledCopy == true)

        do {
            try await port.start()
            #expect(await port.snapshot().state.isRunning)
            #expect(try await messageCount(webPort: settings.webPort) == 0)
            try await port.sendTestEmail()
            #expect(try await messageCount(webPort: settings.webPort) == 1)
            try await port.stop()
            #expect(await port.snapshot().state == .stopped)
            // Stop keeps the captured message: a new start of the same inbox still lists it.
            try await port.start()
            #expect(try await messageCount(webPort: settings.webPort) == 1)
            try await port.stop()
        } catch {
            try? await port.stop()
            throw error
        }
        #expect(await port.snapshot().state == .stopped)
    }

    /// The `total` of the Mailpit message list API of the running inbox on its loopback web port.
    private func messageCount(webPort: UInt16) async throws -> Int {
        let url = try #require(URL(string: "http://127.0.0.1:\(webPort)/api/v1/messages"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        let (data, response) = try await URLSession(configuration: configuration).data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let list = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(list?["total"] as? Int, "The message list has no total.")
    }
}
