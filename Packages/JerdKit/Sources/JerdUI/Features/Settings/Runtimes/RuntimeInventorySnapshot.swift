import Foundation
import JerdManifest
import JerdRuntimes

/// What is installed and in use, for every runtime kind. JerdLive builds it from the site
/// configuration, the service configurations, the CLI tools record, and the managed builds.
public struct RuntimeInventorySnapshot: Hashable, Sendable {
    /// The versions in use for each kind, in any order.
    public var versions: [RuntimeKind: [String]]
    /// The archive digest of the managed build that supplies each registered PHP runtime.
    /// The registrations themselves come from `RegistrationStore`.
    public var phpBuildDigests: [UUID: String]
    /// The managed builds that are in use.
    public var builds: [InstalledBuild]
    /// The pinned releases that the app does not embed and installs on demand (the database engines).
    public var onDemand: [RuntimeRelease]
    /// The on-demand kinds whose install reuses a copy on this Mac, so nothing is downloaded.
    public var reusableOnDemand: Set<RuntimeKind> = []

    public init(
        versions: [RuntimeKind: [String]] = [:], phpBuildDigests: [UUID: String] = [:], builds: [InstalledBuild] = [],
        onDemand: [RuntimeRelease] = []
    ) {
        self.versions = versions
        self.phpBuildDigests = phpBuildDigests
        self.builds = builds
        self.onDemand = onDemand
    }

    /// The pinned release of a kind that has no installed version yet, so the page offers it.
    public func installableRelease(_ kind: RuntimeKind) -> RuntimeRelease? {
        guard installedVersions(kind).isEmpty else { return nil }
        return onDemand.first { $0.kind == kind }
    }

    /// The versions of a kind without duplicates, newest first. Text that is not a version
    /// sorts last, in text order.
    public func installedVersions(_ kind: RuntimeKind) -> [String] {
        Set(versions[kind] ?? []).sorted { left, right in
            switch (RuntimeVersion(left), RuntimeVersion(right)) {
            case (let left?, let right?): left > right
            case (.some, .none): true
            case (.none, .some): false
            case (.none, .none): left < right
            }
        }
    }

    /// True when a build in use installs `release`.
    public func isInstalled(_ release: RuntimeRelease) -> Bool {
        builds.contains { $0.matches(release) }
    }
}
