import Foundation
import JerdFoundation
import JerdWeb
import Testing

@testable import JerdCLICore

@Suite struct CLIRuntimeResolverTests {
    private let normal = runtime("8.5")
    private let isolated = runtime("8.4")
    /// Pure table tests: paths are already resolved.
    private let resolver = CLIRuntimeResolver(resolvePath: { $0 })

    private static func runtime(_ version: String) -> DevelopmentRuntime {
        DevelopmentRuntime(
            cliPath: "/php/\(version)", fpmPath: "/fpm/\(version)", version: version, architectures: [.arm64],
            cliExtensions: [], fpmExtensions: [])
    }

    private func site(
        _ name: String, _ path: String, _ selection: PHPSelection = .followDefault, enabled: Bool = true
    )
        -> Site
    {
        Site(
            displayName: name, projectPath: path, documentRoot: path, hostname: "\(name).test",
            phpSelection: selection, isEnabled: enabled)
    }

    private func configuration(_ sites: [Site]) -> AppConfiguration {
        AppConfiguration(sites: sites, runtimes: [normal, isolated], defaultRuntimeID: normal.id)
    }

    @Test(arguments: [
        ("/code/app", "app", "8.4"),
        ("/code/app/app/Models", "app", "8.4"),
        ("/code/app-other", nil, "8.5"),
        ("/code/ap", nil, "8.5"),
        ("/code", nil, "8.5"),
        ("/code/app/nested", "nested", "8.5"),
        ("/code/app/nested/src", "nested", "8.5"),
        ("/code/app/nestedmore", "app", "8.4"),
    ])
    func deepestContainingProjectSelectsRuntime(directory: String, site expected: String?, version: String) throws {
        let config = configuration([
            site("app", "/code/app", .pinned(isolated.id), enabled: false),
            site("nested", "/code/app/nested"),
        ])
        let selection = try resolver.resolve(config, workingDirectory: directory)
        #expect(selection.site?.displayName == expected)
        #expect(selection.runtime.version == version)
    }

    @Test func disabledSitePinStillApplies() throws {
        let config = configuration([site("app", "/code/app", .pinned(isolated.id), enabled: false)])
        #expect(try resolver.resolve(config, workingDirectory: "/code/app").runtime.id == isolated.id)
    }

    @Test func missingPinFailsWithoutFallback() {
        let config = configuration([site("app", "/code/app", .pinned(UUID()))])
        #expect(
            throws: JerdError.unavailable(
                "The PHP runtime selected for app.test is not installed. Select an installed runtime for this site in Jerd."
            )
        ) { try resolver.resolve(config, workingDirectory: "/code/app/src") }
    }

    @Test func siteFollowingMissingDefaultFailsWithoutFallback() {
        var config = configuration([site("app", "/code/app")])
        config.defaultRuntimeID = nil
        #expect(throws: JerdError.self) { try resolver.resolve(config, workingDirectory: "/code/app") }
    }

    @Test(arguments: [nil, UUID()])
    func outsideProjectsNeedsAnExistingDefault(defaultID: UUID?) {
        var config = configuration([])
        config.defaultRuntimeID = defaultID
        #expect(throws: JerdError.unavailable("Select a default PHP runtime in Jerd.")) {
            try resolver.resolve(config, workingDirectory: "/anywhere")
        }
    }

    @Test func equalDepthMatchesAreRejected() {
        let config = configuration([site("one", "/code/app"), site("two", "/code/other")])
        let aliasing = CLIRuntimeResolver(resolvePath: { $0 == "/code/other" ? "/code/app" : $0 })
        #expect(throws: JerdError.invalid("More than one Jerd site matches this directory.")) {
            try aliasing.resolve(config, workingDirectory: "/code/app/src")
        }
    }

    @Test func pathsAreComparedAfterLexicalCleanup() throws {
        let config = configuration([site("app", "/code/app", .pinned(isolated.id))])
        let selection = try resolver.resolve(config, workingDirectory: "/code/other/../app/./src")
        #expect(selection.site?.hostname == "app.test")
        #expect(selection.selectorName == "app.test")
    }

    @Test func symbolicLinkedWorkingDirectoryUsesTheProjectSelection() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let project = try directory.folder("project")
        try directory.folder("project/src")
        try FileManager.default.createSymbolicLink(at: directory.path("link"), withDestinationURL: project)
        let config = configuration([site("app", project.path, .pinned(isolated.id))])
        let live = CLIRuntimeResolver()
        #expect(try live.resolve(config, workingDirectory: directory.path("link/src").path).runtime.id == isolated.id)
    }

    @Test func liveResolverRejectsTwoSitesThatResolveToOneFolder() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let project = try directory.folder("project")
        let nested = try directory.folder("project/nested")
        try FileManager.default.createSymbolicLink(at: directory.path("alias"), withDestinationURL: project)
        let config = configuration([site("project", project.path), site("alias", directory.path("alias").path)])
        #expect(throws: JerdError.invalid("More than one Jerd site matches this directory.")) {
            try CLIRuntimeResolver().resolve(config, workingDirectory: nested.path)
        }
    }

    @Test func privateTemporaryPathMatchesItsSavedShortForm() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let project = try directory.folder("project")
        let config = configuration([site("app", project.path, .pinned(isolated.id))])
        // getcwd reports /private/var/…; saved paths use Foundation's short /var/… form.
        let reported = "/private" + project.path
        guard FileManager.default.fileExists(atPath: reported) else { return }
        #expect(try CLIRuntimeResolver().resolve(config, workingDirectory: reported).runtime.id == isolated.id)
    }
}
