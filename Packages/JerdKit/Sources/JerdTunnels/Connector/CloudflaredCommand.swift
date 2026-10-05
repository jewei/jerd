import Foundation
import JerdFoundation
import JerdProcess

/// The exact cloudflared command lines. Pure, so tests check every argument without a binary.
package enum CloudflaredCommand {
    /// The only executable name that Jerd runs as cloudflared.
    package static let executableName = "cloudflared"
    /// An explicit empty configuration. It stops cloudflared from reading `~/.cloudflared`,
    /// `/etc/cloudflared`, and `/usr/local/etc/cloudflared`.
    package static let emptyConfiguration = Data("{}\n".utf8)
    /// The timeout of `cloudflared --version`.
    package static let versionTimeout: Duration = .seconds(10)

    /// `cloudflared tunnel --config <instance>/config.yml --no-autoupdate --metrics 127.0.0.1:<port>
    /// --grace-period 15s run`, in the instance folder, with a private `HOME`.
    ///
    /// The token is only in the `TUNNEL_TOKEN` variable, never in an argument. The token and its
    /// secret are redacted from the log. Same-user processes can read a child environment
    /// (`ps -E`), which is the same exposure as the user's own Keychain session.
    package static func connector(_ launch: TunnelLaunch, instance: TunnelInstanceLayout) -> ProcessRequest {
        ProcessRequest(
            executable: launch.runtime.executable,
            arguments: [
                "tunnel", "--config", instance.configurationFile.path, "--no-autoupdate", "--metrics",
                "127.0.0.1:\(launch.registration.metricsPort)", "--grace-period", "15s", "run",
            ],
            workingDirectory: instance.root,
            environment: ["HOME": instance.homeDirectory.path, "TUNNEL_TOKEN": launch.token.value],
            redactedValues: launch.token.redactedValues)
    }

    /// `<executable> --version`.
    package static func version(executable: URL, workingDirectory: URL) -> ProcessRequest {
        ProcessRequest(executable: executable, arguments: ["--version"], workingDirectory: workingDirectory)
    }

    /// The version in a line that starts with `cloudflared version X.Y.Z` followed by a space or the
    /// line end, for example `cloudflared version 2026.9.3 (built 2026-09-03-1200 UTC)`.
    package static func parseVersion(_ output: String) -> String? {
        let pattern = #/^cloudflared version ([0-9]+\.[0-9]+\.[0-9]+)(?=\s|$)/#.anchorsMatchLineEndings()
        return output.firstMatch(of: pattern).map { String($0.1) }
    }

    /// True for a file URL whose last component is `cloudflared` and that the user can execute.
    package static func isCandidate(_ executable: URL) -> Bool {
        executable.isFileURL && executable.lastPathComponent == executableName
            && FileManager.default.isExecutableFile(atPath: executable.path)
    }
}
