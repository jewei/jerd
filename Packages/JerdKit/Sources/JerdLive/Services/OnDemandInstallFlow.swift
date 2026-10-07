import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes

/// The one installation flow of a pinned on-demand runtime, for the Databases page and Runtimes.
///
/// In order: a verified payload that an earlier copy installed is reused; an installed build of
/// the same pin in `runtime-updates/` is reused by `RuntimeInstaller`; only a real download first
/// needs room for the download and the installed copy.
package struct OnDemandInstallFlow: Sendable {
    /// What the flow installed.
    package enum Outcome: Equatable, Sendable {
        case reused(ReusablePayload)
        case built(ManagedRuntime)
    }

    let releases: any OnDemandRuntimeProviding
    let installer: any ManagedRuntimeInstalling
    let layout: DataLayout
    let freeSpace: any FreeSpaceReading

    package init(
        releases: any OnDemandRuntimeProviding, installer: any ManagedRuntimeInstalling, layout: DataLayout,
        freeSpace: any FreeSpaceReading = VolumeFreeSpace()
    ) {
        self.releases = releases
        self.installer = installer
        self.layout = layout
        self.freeSpace = freeSpace
    }

    /// True when `release` is one of the pinned on-demand releases.
    package func isOnDemand(_ release: RuntimeRelease) -> Bool {
        ((try? releases.releases()) ?? []).contains(release)
    }

    /// True when installing `release` downloads nothing: an earlier payload or an installed build
    /// of the pin is on this Mac. It reads receipts only; the install verifies the files.
    package func reusesInstalledCopy(_ release: RuntimeRelease) async -> Bool {
        if await hasBuild(of: release) { return true }
        return (try? await releases.hasReusablePayload(for: release.kind, layout: layout)) ?? false
    }

    package func install(
        _ release: RuntimeRelease, progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> Outcome {
        if let payload = try await releases.reusablePayload(for: release.kind, layout: layout) {
            progress(RuntimeInstallProgress("Using the \(release.title) that is already on this Mac.", 1))
            return .reused(payload)
        }
        if !(await hasBuild(of: release)) { try checkFreeSpace(for: release) }
        return .built(try await installer.install(release, tools: PreparationTools(), progress: progress))
    }

    /// The download and the installed copy exist at the same time, so both must fit.
    func checkFreeSpace(for release: RuntimeRelease) throws {
        guard let required = release.requiredSpace,
            let available = freeSpace.availableBytes(near: layout.runtimes.managedRuntimesDirectory),
            available < required
        else { return }
        throw JerdError.unavailable(
            "Installing \(release.title) needs about \(ByteText.format(required)) of free disk space, and "
                + "\(ByteText.format(available)) is free. Free some space, then try again.")
    }

    private func hasBuild(of release: RuntimeRelease) async -> Bool {
        await installer.list().contains { $0.runtime?.matches(release) == true }
    }
}
