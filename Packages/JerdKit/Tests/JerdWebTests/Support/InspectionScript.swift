import Foundation
import JerdProcess

@testable import JerdWeb

/// Scripted answers of `lipo`, PHP, PHP-FPM, and Caddy for inspection without real runtimes.
struct InspectionScript: Sendable {
    var version = "8.4.0"
    var fpmVersion: String?
    var sapi = "cli"
    var architectures = CPUArchitecture.current.rawValue
    var modules = "[PHP Modules]\nCore\njson\n\n[Zend Modules]\nZend OPcache\n"
    var caddyVersion = "v2.11.4"
    var failing: String?

    /// The answer for one request, or nil when the request is not an inspection command.
    func answer(_ request: ProcessRequest) -> CommandResult? {
        let arguments = request.arguments
        if let failing, arguments.contains(failing) { return CommandResult(status: 1, output: "inspection failed") }
        if request.executable.lastPathComponent == "lipo" { return CommandResult(status: 0, output: architectures) }
        if arguments.starts(with: ["-n", "-r"]) {
            return CommandResult(
                status: 0,
                output: "{\"version\":\"\(version)\",\"sapi\":\"\(sapi)\",\"extensions\":[\"json\",\"Core\"]}")
        }
        if arguments == ["-n", "-v"] {
            return CommandResult(status: 0, output: "PHP \(fpmVersion ?? version) (fpm-fcgi) (built: Jan 1 2026)")
        }
        if arguments == ["-n", "-m"] { return CommandResult(status: 0, output: modules) }
        if arguments == ["version"] { return CommandResult(status: 0, output: "\(caddyVersion) h1:abc=\n") }
        return nil
    }

    /// A runner that answers inspection commands and succeeds for every other command.
    func runner() -> ScriptedCommandRunner {
        ScriptedCommandRunner { request in answer(request) ?? CommandResult(status: 0, output: "") }
    }
}
