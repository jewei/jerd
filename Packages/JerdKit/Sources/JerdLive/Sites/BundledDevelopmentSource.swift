import JerdFoundation
import JerdRuntimes
import JerdWeb

/// Installs the bundled development payload with `BundledRuntimeBootstrap` and inspects PHP and
/// Caddy with the JerdWeb inspectors, in the bootstrap inspection folder.
package struct BundledDevelopmentSource: DevelopmentRuntimeSource {
    let bootstrap: BundledRuntimeBootstrap
    let layout: DataLayout
    let php: PHPRuntimeInspector
    let caddy: CaddyRuntimeInspector

    package init(
        bootstrap: BundledRuntimeBootstrap, layout: DataLayout, php: PHPRuntimeInspector = PHPRuntimeInspector(),
        caddy: CaddyRuntimeInspector = CaddyRuntimeInspector()
    ) {
        self.bootstrap = bootstrap
        self.layout = layout
        self.php = php
        self.caddy = caddy
    }

    package func isNeeded(for configuration: AppConfiguration) async throws -> Bool {
        try await bootstrap.needsDevelopmentRuntimes(
            hasPHP: !configuration.runtimes.isEmpty, hasCaddy: configuration.caddy != nil)
    }

    package func install() async throws -> DevelopmentRuntimeRecords {
        let installed = try await bootstrap.installDevelopment()
        guard let fpm = installed.php.secondaryExecutable else {
            throw JerdError.invalid("The bundled PHP has no PHP-FPM executable.")
        }
        let work = layout.runtimes.bootstrapInspectionDirectory
        return DevelopmentRuntimeRecords(
            php: try await php.inspect(cli: installed.php.executable, fpm: fpm, workDirectory: work),
            caddy: try await caddy.inspect(installed.caddy.executable, workDirectory: work))
    }
}
