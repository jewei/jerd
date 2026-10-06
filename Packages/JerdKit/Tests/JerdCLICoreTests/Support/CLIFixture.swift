import Foundation
import JerdFoundation
import JerdRuntimes
import JerdTestSupport
import JerdWeb

/// A temporary Jerd installation: a data root, a home folder, managed PHP builds with receipts,
/// the saved configuration, and the Composer and Laravel tool record.
struct CLIFixture {
    /// A fake PHP: prints its argument vector, the launcher variables, and exits with status 7.
    static let fakePHP = """
        #!/bin/sh
        for argument in "$0" "$@"; do printf 'arg=%s\\n' "$argument"; done
        printf 'PATH=%s\\n' "$PATH"
        printf 'SCAN=%s\\n' "${PHP_INI_SCAN_DIR-unset}"
        exit 7

        """

    let directory: TemporaryDirectory
    let layout: DataLayout
    let home: URL

    init() throws {
        directory = try TemporaryDirectory(" cli café")
        layout = DataLayout(root: try directory.folder("home/Library/Application Support/Jerd"))
        home = directory.path("home")
    }

    func remove() { directory.remove() }

    /// Installs a managed PHP build with a legacy development receipt and returns its record.
    @discardableResult
    func installPHP(_ version: String, id: UUID = UUID()) throws -> DevelopmentRuntime {
        let build = layout.runtimes.developmentRuntimesDirectory.appendingPathComponent("php-\(version)-arm64")
        try OwnedDirectory.create(build)
        let php = build.appendingPathComponent("php-native-\(version)")
        try Data(Self.fakePHP.utf8).write(to: php)
        chmod(php.path, 0o700)
        let receipt: [String: Any] = [
            "schemaVersion": 1, "archiveSHA256": String(repeating: "a", count: 64),
            "fileSHA256": [php.lastPathComponent: try FileDigest.hexSHA256(of: php)],
        ]
        try AtomicFile.write(
            try JSONSerialization.data(withJSONObject: receipt), to: build.appendingPathComponent("jerd-receipt.json"))
        return runtime(version, cliPath: php.path, id: id)
    }

    func runtime(_ version: String, cliPath: String, id: UUID = UUID()) -> DevelopmentRuntime {
        DevelopmentRuntime(
            id: id, cliPath: cliPath, fpmPath: cliPath + "-fpm", version: version, architectures: [.arm64],
            cliExtensions: ["Core"], fpmExtensions: ["Core"], inspectedAt: Date(timeIntervalSinceReferenceDate: 0))
    }

    /// Saves `configuration.json` through the one codec.
    func save(_ configuration: AppConfiguration) throws {
        try AtomicFile.write(try ConfigurationCodec.encode(configuration), to: layout.configurationFile)
    }

    /// Saves a configuration whose default is `runtime` and returns it.
    @discardableResult
    func saveDefault(
        _ runtime: DevelopmentRuntime, sites: [Site] = [], others: [DevelopmentRuntime] = []
    )
        throws -> AppConfiguration
    {
        let configuration = AppConfiguration(sites: sites, runtimes: [runtime] + others, defaultRuntimeID: runtime.id)
        try save(configuration)
        return configuration
    }

    /// Writes the Composer and Laravel scripts and their tool record.
    @discardableResult
    func installCompanions() throws -> CLICompanions {
        let composer = try directory.file(
            "home/Library/Application Support/Jerd/runtimes/composer-2/composer.phar", "<?php // composer")
        let laravel = try directory.file(
            "home/Library/Application Support/Jerd/runtime-updates/laravel-5/vendor/bin/laravel", "<?php // laravel")
        let companions = CLICompanions(
            composerPath: composer.path, laravelPath: laravel.path, composerVersion: "2.10.3",
            laravelVersion: "5.32.0")
        try AtomicFile.write(try JSONEncoder().encode(companions), to: layout.runtimes.cliToolsFile)
        return companions
    }

    /// A registered site for `project` (a folder below the temporary folder, created when missing).
    func site(
        _ name: String, project: String, selection: PHPSelection = .followDefault, enabled: Bool = true
    )
        throws -> Site
    {
        let folder = try directory.folder(project)
        return Site(
            displayName: name, projectPath: folder.path, documentRoot: folder.path, hostname: "\(name).test",
            phpSelection: selection, isEnabled: enabled)
    }
}
