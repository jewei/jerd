import Foundation
import JerdArchive
import JerdFoundation
import JerdManifest

/// PHP from a `lerd-php` archive: the CLI and FPM of the release branch and the two notice files.
package struct PHPPreparer: RuntimePreparing {
    package init() {}

    /// The CLI and FPM names of a PHP version, for example `php-native-8.5` (from the version, never fixed; P-B1).
    package static func executables(version: String) throws -> (cli: String, fpm: String) {
        guard let parsed = RuntimeVersion(version) else {
            throw JerdError.invalid("The update metadata is incomplete or invalid.")
        }
        let branch = parsed.prefix(2)
        return ("php-native-\(branch)", "php-native-fpm-\(branch)")
    }

    package func prepare(_ context: PreparationContext) async throws {
        let (cli, fpm) = try Self.executables(version: context.release.version)
        let names: Set<String> = [cli, fpm, "THIRD-PARTY-NOTICES.txt", "BUILD-INFO.txt"]
        try await RuntimePreparers.extract(
            try context.requireArtifact(), to: context.payload,
            policy: ExtractionPolicy { names.contains($0.string) })
        try RuntimePreparers.requireFiles([cli, fpm], in: context.payload, kind: .php)
    }
}
