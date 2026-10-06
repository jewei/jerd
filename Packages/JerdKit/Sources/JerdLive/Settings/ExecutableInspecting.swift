import Foundation
import JerdWeb

/// Inspects explicit PHP and Caddy executables into site configuration records.
/// `ExecutableInspector` is the live type; tests use a fake that runs nothing.
package protocol ExecutableInspecting: Sendable {
    func inspectPHP(cli: URL, fpm: URL) async throws -> DevelopmentRuntime
    func inspectCaddy(_ executable: URL) async throws -> CaddyRuntime
}
