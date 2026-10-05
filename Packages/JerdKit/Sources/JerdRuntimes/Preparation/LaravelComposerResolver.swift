import Foundation
import JerdFoundation

/// The Laravel installer, installed by Composer with plugins and scripts disabled.
///
/// A managed update resolves `laravel/installer` at the release version (`composer update`).
/// A pinned payload installs exactly the committed lock (`composer install`). Composer, its
/// cache, and `HOME` live in the staging folder, so no tool can write into the payload's
/// receipt-listed files by accident (fixes P-I8).
package struct LaravelComposerResolver: RuntimePreparing {
    package static let timeout: Duration = .seconds(900)

    package init() {}

    /// The exact `composer.json` of a managed update: compact, sorted keys.
    package static func projectFile(version: String) throws -> Data {
        let document: [String: Any] = [
            "require": ["laravel/installer": version],
            "config": [
                "allow-plugins": false, "secure-http": true, "preferred-install": "dist", "notify-on-install": false,
            ],
        ]
        return try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
    }

    /// The Composer command after `php -n composer.phar`.
    package static func composerArguments(locked: Bool) -> [String] {
        [
            locked ? "install" : "update", "--no-dev", "--no-plugins", "--no-scripts", "--prefer-dist",
            "--no-interaction",
            "--no-progress",
        ]
    }

    package func prepare(_ context: PreparationContext) async throws {
        guard let php = context.tools.phpCLI, let composer = context.tools.composer else {
            throw JerdError.unavailable("Install PHP and Composer before the Laravel installer.")
        }
        let locked = try await writeProject(context)
        let home = context.staging.appendingPathComponent("composer-home", isDirectory: true)
        try OwnedDirectory.create(home.appendingPathComponent("home"))
        try await context.run(
            php.path, ["-n", composer.path] + Self.composerArguments(locked: locked), in: context.payload,
            environment: [
                "HOME": home.appendingPathComponent("home").path, "COMPOSER_HOME": home.path,
                "COMPOSER_CACHE_DIR": home.appendingPathComponent("cache").path, "COMPOSER_NO_INTERACTION": "1",
                "PHP_INI_SCAN_DIR": "", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null",
            ],
            timeout: Self.timeout)
    }

    /// Writes the project files. Returns true for a locked (pinned) project.
    private func writeProject(_ context: PreparationContext) async throws -> Bool {
        let payload = context.payload
        switch context.release.artifact {
        case .lockedComposerProject(let directory):
            try await BlockingWork.run {
                for name in ["composer.json", "composer.lock"] {
                    try FileManager.default.copyItem(
                        at: directory.appendingPathComponent(name), to: payload.appendingPathComponent(name))
                }
            }
            return true
        default:
            let data = try Self.projectFile(version: context.release.version)
            try AtomicFile.write(data, to: payload.appendingPathComponent("composer.json"), durability: .standard)
            return false
        }
    }
}
