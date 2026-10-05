import Foundation
import JerdFoundation

/// Creates the private folders of a run and writes its generated files (all mode 0700 and 0600).
enum EngineFiles {
    /// The configuration, log, certificate, and empty INI folders, and every pool folder.
    static func createFolders(_ plan: EngineStartPlan) throws {
        let environment = plan.layout.environment
        for folder in [
            environment.root, environment.configurationDirectory, environment.logsDirectory,
            environment.certificatesDirectory, environment.emptyINIDirectory,
        ] {
            try OwnedDirectory.create(folder)
        }
        for pool in plan.pools {
            try OwnedDirectory.create(pool.layout.configurationDirectory)
            try OwnedDirectory.create(pool.layout.logsDirectory)
        }
    }

    /// The pool file and the FPM `php.ini` (with the CA bundle section when one is given).
    static func writePool(_ pool: EngineStartPlan.Pool, caBundle: URL?) throws {
        try AtomicFile.write(
            Data(try FPMPoolRenderer.render(socket: pool.layout.socket).utf8), to: pool.layout.fpmConfigurationFile)
        try AtomicFile.write(Data(try PHPIniPolicy.fpmFile(caBundle: caBundle).utf8), to: pool.layout.phpINIFile)
    }

    /// `configuration/caddy.json`.
    static func writeCaddy(_ plan: EngineStartPlan) throws {
        try AtomicFile.write(try plan.caddyConfiguration(), to: plan.layout.environment.caddyConfigurationFile)
    }
}
