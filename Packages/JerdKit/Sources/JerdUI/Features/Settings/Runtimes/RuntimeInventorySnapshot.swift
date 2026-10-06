import Foundation
import JerdManifest
import JerdRuntimes

/// What is installed and in use, for every runtime kind. JerdLive builds it from the site
/// configuration, the service configurations, the CLI tools record, and the managed builds.
public struct RuntimeInventorySnapshot: Hashable, Sendable {
    /// The versions in use for each kind, in any order.
    public var versions: [RuntimeKind: [String]]
    /// The registered PHP runtimes, in configuration order.
    public var php: [RegisteredPHP]
    public var defaultPHPID: UUID?
    /// The managed builds that are in use.
    public var builds: [InstalledBuild]

    public init(
        versions: [RuntimeKind: [String]] = [:], php: [RegisteredPHP] = [], defaultPHPID: UUID? = nil,
        builds: [InstalledBuild] = []
    ) {
        self.versions = versions
        self.php = php
        self.defaultPHPID = defaultPHPID
        self.builds = builds
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

    /// The default PHP runtime, if one is registered.
    public var defaultPHP: RegisteredPHP? {
        php.first { $0.id == defaultPHPID }
    }

    /// True when a build in use installs `release`.
    public func isInstalled(_ release: RuntimeRelease) -> Bool {
        builds.contains { $0.matches(release) }
    }
}
