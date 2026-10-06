import os

/// The launch steps before any feature loads. Each runs off the main actor, once per launch.
/// A failure is logged and never stops the launch: the features report their own problems.
package struct LaunchPreparation: Sendable {
    static let log = Logger(subsystem: "dev.jerd.app", category: "launch")

    let staging: [any StagingCleaning]
    /// Nil when the data root is not the current user's (a Debug run with its own data root).
    let launcher: (any LauncherRefreshing)?

    package init(staging: [any StagingCleaning], launcher: (any LauncherRefreshing)?) {
        self.staging = staging
        self.launcher = launcher
    }

    package func run() async {
        for cleaner in staging {
            for folder in await cleaner.removeAbandonedStaging() {
                Self.log.notice("Removed the abandoned staging folder \(folder, privacy: .public).")
            }
        }
        guard let launcher else { return }
        do {
            try await launcher.refreshLauncherIfInstalled()
        } catch {
            Self.log.error(
                "The command-line launcher was not refreshed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
