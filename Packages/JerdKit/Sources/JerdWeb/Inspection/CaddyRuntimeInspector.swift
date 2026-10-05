import Foundation
import JerdFoundation
import JerdProcess

/// Inspects an explicit Caddy executable into a `CaddyRuntime` record.
public struct CaddyRuntimeInspector: Sendable {
    private let commands: any CommandRunning

    public init(commands: any CommandRunning = CommandRunner()) {
        self.commands = commands
    }

    /// Requires the current architecture and a Caddy 2 release version (`v2.…`).
    public func inspect(_ binary: URL, workDirectory: URL) async throws -> CaddyRuntime {
        let steps = InspectionCommands(commands: commands, workDirectory: workDirectory)
        try steps.prepare()
        let binary = try InspectionCommands.resolve(binary)
        let architectures = try await steps.architectures(binary)
        guard architectures.contains(.current) else {
            throw JerdError.unavailable("Caddy does not contain the current architecture.")
        }
        let version = try await steps.output(binary, ["version"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard version.hasPrefix("v2.") else {
            throw JerdError.invalid("Select a Caddy 2 executable with a release version.")
        }
        return CaddyRuntime(path: binary.path, version: version, architectures: architectures)
    }
}
