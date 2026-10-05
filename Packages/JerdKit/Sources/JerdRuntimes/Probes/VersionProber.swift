import Foundation
import JerdFoundation
import JerdManifest

/// Runs the version probes of a prepared payload and returns the proven version and executables.
package struct VersionProber: Sendable {
    /// The result of the probes.
    package struct Outcome: Equatable, Sendable {
        /// The version that the runtime reports (the engine version for PostgreSQL).
        package let version: String
        package let executable: RelativePath
        /// PHP-FPM for PHP, otherwise nil.
        package let secondaryExecutable: RelativePath?
    }

    package let context: PreparationContext

    package init(context: PreparationContext) { self.context = context }

    package func probe() async throws -> Outcome {
        let release = context.release
        let probes = try VersionProbe.probes(for: release.kind, version: release.version)
        var versions: [String] = []
        for probe in probes {
            let output = try await run(probe)
            guard let version = probe.pattern.version(in: output, expected: release.version) else {
                throw probe.pattern.mismatch(title: release.kind.title)
            }
            versions.append(version)
        }
        guard let main = probes.first, let version = versions.first else {
            throw JerdError.invalid("The installed \(release.kind.title) did not report the expected version.")
        }
        return Outcome(
            version: version, executable: main.executable, secondaryExecutable: probes.dropFirst().first?.executable)
    }

    private func run(_ probe: VersionProbe) async throws -> String {
        let file = probe.executable.url(in: context.payload)
        if probe.runsWithPHP {
            guard let php = context.tools.phpCLI else {
                throw JerdError.unavailable("Select a PHP runtime before installing CLI tools.")
            }
            return try await context.run(
                php.path, ["-n", file.path] + probe.arguments, in: context.staging,
                environment: ["PHP_INI_SCAN_DIR": ""])
        }
        guard chmod(file.path, 0o700) == 0 else {
            throw JerdError.invalid("The \(context.release.kind.title) package does not contain \(probe.executable).")
        }
        return try await context.run(
            file.path, probe.arguments, in: context.staging, environment: ["PHP_INI_SCAN_DIR": ""])
    }
}
