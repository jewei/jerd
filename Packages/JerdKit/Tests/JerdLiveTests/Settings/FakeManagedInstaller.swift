import JerdManifest
import JerdRuntimes

@testable import JerdLive

/// A managed installer with a fixed listing. `install` returns the listed build that matches
/// the release and records the tools it received.
actor FakeManagedInstaller: ManagedRuntimeInstalling, RuntimeCatalogChecking {
    let listing: [ManagedRuntimeListing]
    /// Builds that `install` produces as if it downloaded them: not listed before the install.
    let downloads: [ManagedRuntime]
    private(set) var tools: [PreparationTools] = []
    private(set) var checked: [RuntimeKind] = []

    init(_ builds: [ManagedRuntime] = [], unusable: [ManagedRuntimeListing] = [], downloads: [ManagedRuntime] = []) {
        listing = unusable + builds.map(ManagedRuntimeListing.runtime)
        self.downloads = downloads
    }

    private(set) var stagingCleanups = 0

    func list() -> [ManagedRuntimeListing] { listing }

    func removeAbandonedStaging() -> [String] {
        stagingCleanups += 1
        return [".staging-1"]
    }

    func install(
        _ release: RuntimeRelease, tools: PreparationTools,
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) throws -> ManagedRuntime {
        self.tools.append(tools)
        guard let build = (listing.compactMap(\.runtime) + downloads).first(where: { $0.matches(release) }) else {
            throw CancellationError()
        }
        return build
    }

    func check(_ kind: RuntimeKind) -> RuntimeUpdateCheck {
        checked.append(kind)
        return RuntimeUpdateCheck(kind: kind, releases: [], checkedAt: .distantPast, error: "offline")
    }
}
