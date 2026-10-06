import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import JerdUI

/// A runtime inventory in memory. An activated build joins the snapshot, like the live owners.
public actor InMemoryRuntimeInventory: RuntimeInventory {
    public private(set) var inventory: RuntimeInventorySnapshot
    public var snapshotFailure: String?
    public var results: [RuntimeKind: RuntimeUpdateCheck]
    public var installBehavior: InstallBehavior
    public var activationFailure: String?
    public var defaultFailure: String?
    public private(set) var checkedKinds: [RuntimeKind] = []
    public private(set) var installed: [RuntimeRelease] = []
    public private(set) var activations: [(build: InstalledBuild, useAsDefault: Bool)] = []
    public private(set) var defaultRequests: [UUID] = []

    public init(
        inventory: RuntimeInventorySnapshot = RuntimeInventorySnapshot(),
        results: [RuntimeKind: RuntimeUpdateCheck] = [:], installBehavior: InstallBehavior = .succeed
    ) {
        self.inventory = inventory
        self.results = results
        self.installBehavior = installBehavior
    }

    public func configure(_ change: @Sendable (isolated InMemoryRuntimeInventory) -> Void) {
        change(self)
    }

    public func snapshot() async throws -> RuntimeInventorySnapshot {
        if let snapshotFailure { throw JerdError.corrupt(snapshotFailure) }
        return inventory
    }

    public func check(_ kind: RuntimeKind) async -> RuntimeUpdateCheck {
        checkedKinds.append(kind)
        return results[kind] ?? RuntimeUpdateCheck(kind: kind, releases: [], checkedAt: SampleData.now, error: nil)
    }

    public func install(
        _ release: RuntimeRelease, progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> InstalledBuild {
        installed.append(release)
        switch installBehavior {
        case .succeed:
            progress(RuntimeInstallProgress("Downloading \(release.kind.title) \(release.version)…", 0.5))
            return InstalledBuild(
                kind: release.kind, version: release.version, releaseVersion: release.version,
                archiveSHA256: release.archiveSHA256 ?? SampleData.digest)
        case .fail(let message):
            throw JerdError.unavailable(message)
        case .suspend(let report):
            progress(report)
            while true {
                try await Task.sleep(for: .seconds(3600))
            }
        }
    }

    public func activate(_ build: InstalledBuild, useAsDefault: Bool) async throws {
        activations.append((build, useAsDefault))
        if let activationFailure { throw JerdError.invalid(activationFailure) }
        inventory.builds.append(build)
        inventory.versions[build.kind, default: []].append(build.version)
    }

    public func setDefaultPHP(_ id: UUID) async throws {
        defaultRequests.append(id)
        if let defaultFailure { throw JerdError.invalid(defaultFailure) }
        inventory.defaultPHPID = id
    }
}
