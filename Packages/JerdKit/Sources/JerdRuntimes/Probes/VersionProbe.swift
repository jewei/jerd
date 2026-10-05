import Foundation
import JerdFoundation
import JerdManifest

/// One command that proves the version of a prepared runtime (table I12), as data.
package struct VersionProbe: Sendable, Equatable {
    /// The file to run, relative to the payload.
    package let executable: RelativePath
    package let arguments: [String]
    /// True for PHP scripts (Composer, Laravel), which run as `<php> -n <script> <arguments>`.
    package let runsWithPHP: Bool
    package let pattern: VersionPattern

    /// The probes of a kind. The first probe names the main executable; PHP also probes FPM.
    package static func probes(for kind: RuntimeKind, version: String) throws -> [VersionProbe] {
        switch kind {
        case .php:
            let (cli, fpm) = try PHPPreparer.executables(version: version)
            return [
                try probe(cli, ["-n", "-v"], .php(sapi: "cli")), try probe(fpm, ["-n", "-v"], .php(sapi: "fpm-fcgi")),
            ]
        case .caddy: return [try probe("caddy", ["version"], .caddy)]
        case .mysql: return [try probe("bin/mysqld", ["--no-defaults", "--version"], .bounded)]
        case .postgresql: return [try probe("bin/postgres", ["--version"], .postgresEngine)]
        case .redis: return [try probe("bin/redis-server", ["--version"], .redis)]
        case .mailpit: return [try probe("mailpit", ["version", "--no-release-check"], .bounded)]
        case .rustfs: return [try probe("rustfs", ["--version"], .bounded)]
        case .cloudflared: return [try probe("cloudflared", ["--version"], .cloudflared)]
        case .composer:
            return [try probe("composer.phar", ["--version", "--no-ansi", "--no-plugins"], .bounded, php: true)]
        case .laravel:
            return [try probe("vendor/laravel/installer/bin/laravel", ["--version", "--no-ansi"], .bounded, php: true)]
        }
    }

    private static func probe(
        _ path: String, _ arguments: [String], _ pattern: VersionPattern, php: Bool = false
    ) throws -> VersionProbe {
        guard let executable = RelativePath(path) else {
            throw JerdError.invalid("The runtime path \(path) is unsafe.")
        }
        return VersionProbe(executable: executable, arguments: arguments, runsWithPHP: php, pattern: pattern)
    }
}
