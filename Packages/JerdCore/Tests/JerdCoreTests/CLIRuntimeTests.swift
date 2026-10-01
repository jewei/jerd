import Foundation
import Testing
@testable import JerdCore

struct CLIRuntimeTests {
    private func runtime(_ version: String) -> DevelopmentRuntime {
        DevelopmentRuntime(cliPath: "/php/\(version)", fpmPath: "/fpm/\(version)", version: version,
                           architectures: [.arm64], cliExtensions: [], fpmExtensions: [])
    }

    @Test func selectsPinnedSiteFromNestedDirectoryAndDefaultOutside() throws {
        let normal = runtime("8.5"), isolated = runtime("8.4")
        var config = AppConfiguration()
        config.runtimes = [normal, isolated]; config.defaultRuntimeID = normal.id
        config.sites = [Site(displayName: "App", projectPath: "/tmp/jerd-project", documentRoot: "/tmp/jerd-project/public",
            hostname: "app.test", phpSelection: .pinned(isolated.id), isEnabled: false)]
        #expect(try CLIRuntimeSelection.resolve(configuration: config, workingDirectory: URL(fileURLWithPath: "/tmp/jerd-project/app/Models")).runtime.id == isolated.id)
        #expect(try CLIRuntimeSelection.resolve(configuration: config, workingDirectory: URL(fileURLWithPath: "/tmp/jerd-project-other")).runtime.id == normal.id)
        config.sites.append(Site(displayName: "Nested", projectPath: "/tmp/jerd-project/nested", documentRoot: "/tmp/jerd-project/nested",
            hostname: "nested.test", phpSelection: .followDefault))
        #expect(try CLIRuntimeSelection.resolve(configuration: config, workingDirectory: URL(fileURLWithPath: "/tmp/jerd-project/nested/src")).runtime.id == normal.id)
    }

    @Test func missingPinDoesNotFallBackAndSymlinksUseProjectSelection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("project"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.appendingPathComponent("project"))
        let normal = runtime("8.5")
        var config = AppConfiguration(); config.runtimes = [normal]; config.defaultRuntimeID = normal.id
        config.sites = [Site(displayName: "App", projectPath: root.appendingPathComponent("project").path,
            documentRoot: root.appendingPathComponent("project").path, hostname: "app.test", phpSelection: .pinned(UUID()))]
        #expect(throws: JerdError.self) {
            try CLIRuntimeSelection.resolve(configuration: config, workingDirectory: root.appendingPathComponent("link"))
        }
    }
}
