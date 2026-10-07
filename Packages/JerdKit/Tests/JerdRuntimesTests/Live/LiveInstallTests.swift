import Foundation
import JerdFoundation
import JerdManifest
import JerdProcess
import JerdRuntimes
import Testing

/// Opt-in installation of real releases into a temporary folder: `JERD_RUNTIME_NETWORK=1` and
/// `JERD_RUNTIME_INSTALL=mailpit,caddy` (a comma-separated list of kinds without PHP tools). For RustFS,
/// `JERD_LZMA_LIBRARY` and `JERD_LZMA_LICENSE` name a reviewed XZ library and its license.
@Suite(
    .enabled(
        if: ProcessInfo.processInfo.environment["JERD_RUNTIME_NETWORK"] == "1"
            && ProcessInfo.processInfo.environment["JERD_RUNTIME_INSTALL"] != nil))
struct LiveInstallTests {
    @Test func newestReleasesInstallAndVerify() async throws {
        let kinds = (ProcessInfo.processInfo.environment["JERD_RUNTIME_INSTALL"] ?? "")
            .split(separator: ",").compactMap { RuntimeKind(rawValue: String($0)) }
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let fetcher = URLSessionFetcher()
        let catalog = RuntimeCatalog(fetcher: fetcher)
        let installer = RuntimeInstaller(directory: folder.path("runtime-updates"), fetcher: fetcher)
        let environment = ProcessInfo.processInfo.environment
        var tools = PreparationTools()
        if let library = environment["JERD_LZMA_LIBRARY"], let license = environment["JERD_LZMA_LICENSE"] {
            tools.lzma = SupportLibrary(library: URL(fileURLWithPath: library), license: URL(fileURLWithPath: license))
        }
        for kind in kinds {
            let release = try #require(await catalog.check(kind).releases.first, "\(kind.title)")
            let runtime = try await installer.install(release, tools: tools)
            #expect(runtime.matches(release))
            let store = ManagedRuntimeStore(directory: folder.path("runtime-updates"))
            try store.verify(try store.receipt(at: runtime.directory), at: runtime.directory)
        }
        #expect(await installer.list().compactMap(\.runtime).count == kinds.count)
    }
}
