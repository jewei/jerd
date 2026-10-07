import Foundation
import JerdFoundation
import JerdWeb

/// The JerdWeb inspectors with the activation and import work folder
/// (`runtime-inspection/empty-ini`), so an inspection never reads a user `php.ini`.
package struct ExecutableInspector: ExecutableInspecting {
    let workDirectory: URL
    let php: PHPRuntimeInspector
    let caddy: CaddyRuntimeInspector

    package init(
        layout: DataLayout, php: PHPRuntimeInspector = PHPRuntimeInspector(),
        caddy: CaddyRuntimeInspector = CaddyRuntimeInspector()
    ) {
        workDirectory = layout.runtimes.inspectionDirectory
        self.php = php
        self.caddy = caddy
    }

    package func inspectPHP(cli: URL, fpm: URL) async throws -> DevelopmentRuntime {
        try await php.inspect(cli: cli, fpm: fpm, workDirectory: workDirectory)
    }

    package func inspectCaddy(_ executable: URL) async throws -> CaddyRuntime {
        try await caddy.inspect(executable, workDirectory: workDirectory)
    }
}
