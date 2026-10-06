import Foundation
import JerdFoundation
import JerdProcess

/// Inspects the runtimes of a plan again and refuses a change since the saved inspection.
///
/// It is the one place for this check, used by both preflight and start.
struct RuntimeDriftCheck: Sendable {
    let commands: any CommandRunning

    /// Requires the same version and extension lists as the saved record.
    func requireUnchanged(_ runtime: DevelopmentRuntime, workDirectory: URL) async throws {
        let actual = try await PHPRuntimeInspector(commands: commands).inspect(
            cli: URL(fileURLWithPath: runtime.cliPath), fpm: URL(fileURLWithPath: runtime.fpmPath),
            workDirectory: workDirectory)
        guard actual.version == runtime.version, actual.cliExtensions == runtime.cliExtensions,
            actual.fpmExtensions == runtime.fpmExtensions
        else { throw JerdError.unavailable("PHP changed since inspection. Inspect and select the runtime again.") }
    }

    /// Requires the same version as the saved record.
    func requireUnchanged(_ caddy: CaddyRuntime, workDirectory: URL) async throws {
        let actual = try await CaddyRuntimeInspector(commands: commands).inspect(
            URL(fileURLWithPath: caddy.path), workDirectory: workDirectory)
        guard actual.version == caddy.version else {
            throw JerdError.unavailable("Caddy changed since inspection. Select it again.")
        }
    }

    /// The distinct runtimes of a plan in plan order. One ID with two different records is refused.
    static func distinctRuntimes(of plan: ServingPlan) throws -> [DevelopmentRuntime] {
        var runtimes: [DevelopmentRuntime] = []
        for entry in plan.sites {
            if let known = runtimes.first(where: { $0.id == entry.runtime.id }) {
                guard known == entry.runtime else {
                    throw JerdError.invalid("A PHP runtime ID has conflicting settings.")
                }
            } else {
                runtimes.append(entry.runtime)
            }
        }
        return runtimes
    }
}
