/// Replaces an outdated command-line launcher in `bin/`. `LiveCommandLineTools` is the live type.
package protocol LauncherRefreshing: Sendable {
    @discardableResult
    func refreshLauncherIfInstalled() async throws -> Bool
}
