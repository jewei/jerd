import Foundation
import JerdFoundation
import JerdProcess

/// Everything one preparation step may use: the verified artifact, the folders, and the effects.
package struct PreparationContext: Sendable {
    package let release: RuntimeRelease
    /// The verified download, or nil for a Composer resolution.
    package let artifact: URL?
    /// The folder that becomes the runtime. It starts empty.
    package let payload: URL
    /// A private work folder that is removed after the installation.
    package let staging: URL
    package let tools: PreparationTools
    package let commands: any CommandRunning
    package let fetcher: any HTTPFetching
    /// The oldest macOS that a build from source must run on.
    package let minimumMacOS: MinimumMacOS

    package init(
        release: RuntimeRelease, artifact: URL?, payload: URL, staging: URL, tools: PreparationTools,
        commands: any CommandRunning, fetcher: any HTTPFetching, minimumMacOS: MinimumMacOS
    ) {
        self.release = release
        self.artifact = artifact
        self.payload = payload
        self.staging = staging
        self.tools = tools
        self.commands = commands
        self.fetcher = fetcher
        self.minimumMacOS = minimumMacOS
    }

    /// The verified download. Preparations of archives require it.
    package func requireArtifact() throws -> URL {
        guard let artifact else { throw JerdError.invalid("The runtime download has no verification method.") }
        return artifact
    }

    /// Runs a tool of a preparation step and returns its output.
    /// - Throws: `.processFailed("Runtime preparation failed: <last 3000 characters>")` for a non-zero status.
    @discardableResult
    package func run(
        _ executable: String, _ arguments: [String], in folder: URL, environment: [String: String] = [:],
        timeout: Duration = .seconds(60)
    ) async throws -> String {
        let request = ProcessRequest(
            executable: URL(fileURLWithPath: executable), arguments: arguments, workingDirectory: folder,
            environment: environment)
        let result = try await commands.run(request, timeout: timeout)
        guard result.succeeded else {
            throw JerdError.processFailed("Runtime preparation failed: \(result.diagnosticOutput.suffix(3_000))")
        }
        return result.output
    }
}
