import Foundation
import JerdFoundation
import JerdProcess

/// Inspects an explicit PHP CLI and PHP-FPM pair into a `DevelopmentRuntime` record.
///
/// Rules: links are resolved and Herd binaries refused; both executables must contain the current
/// architecture; the CLI must report SAPI `cli`; FPM must report the same full version and SAPI
/// `fpm-fcgi`; FPM must list its modules. The result gets a new ID and the current time.
public struct PHPRuntimeInspector: Sendable {
    /// App-owned code that reports the CLI version, SAPI, and extensions. It runs no project file.
    static let script =
        "echo json_encode(['version'=>PHP_VERSION,'sapi'=>PHP_SAPI,'extensions'=>get_loaded_extensions()]);"

    private let commands: any CommandRunning
    private let now: @Sendable () -> Date

    public init(commands: any CommandRunning = CommandRunner(), now: @escaping @Sendable () -> Date = Date.init) {
        self.commands = commands
        self.now = now
    }

    public func inspect(cli: URL, fpm: URL, workDirectory: URL) async throws -> DevelopmentRuntime {
        let steps = InspectionCommands(commands: commands, workDirectory: workDirectory)
        try steps.prepare()
        let cli = try InspectionCommands.resolve(cli)
        let fpm = try InspectionCommands.resolve(fpm)
        let fpmArchitectures = try await steps.architectures(fpm)
        let common = try await steps.architectures(cli).filter(fpmArchitectures.contains)
        guard common.contains(.current) else {
            throw JerdError.unavailable("Both PHP executables must contain the current process architecture.")
        }
        let info = try decode(try await steps.output(cli, ["-n", "-r", Self.script]))
        guard info.sapi == "cli" else { throw JerdError.invalid("Select a PHP CLI executable.") }
        let version = try await steps.output(fpm, ["-n", "-v"])
        let fields = version.split(whereSeparator: \.isWhitespace)
        guard fields.count > 2, fields[0] == "PHP", fields[1] == Substring(info.version), version.contains("fpm-fcgi")
        else {
            throw JerdError.invalid("PHP CLI and PHP-FPM must report the same full version and the correct SAPI.")
        }
        let modules = PHPModuleList.parse(try await steps.output(fpm, ["-n", "-m"]))
        guard !modules.isEmpty else { throw JerdError.invalid("PHP-FPM returned no extension list.") }
        return DevelopmentRuntime(
            cliPath: cli.path, fpmPath: fpm.path, version: info.version, architectures: common,
            cliExtensions: info.extensions.sorted(), fpmExtensions: modules, inspectedAt: now())
    }

    private func decode(_ output: String) throws -> CLIInformation {
        do {
            return try JSONDecoder().decode(CLIInformation.self, from: Data(output.utf8))
        } catch {
            throw JerdError.invalid("The selected CLI did not return valid PHP inspection data.")
        }
    }

    private struct CLIInformation: Decodable {
        let version: String
        let sapi: String
        let extensions: [String]
    }
}
