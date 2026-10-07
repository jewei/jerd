import JerdManifest
import JerdRuntimes
import JerdUI
import os

extension OnDemandInstallFlow {
    /// The offer of the pinned release of `kind` for its service page (RustFS, Mailpit), and whether
    /// its install reuses a copy on this Mac. A missing or bad catalog offers nothing and is logged;
    /// the page then leads to Runtimes.
    package func offer(of kind: RuntimeKind, log: Logger) async -> ServiceRuntimeOffer? {
        let release: RuntimeRelease?
        do {
            release = try self.release(of: kind)
        } catch {
            log.error(
                "\(kind.title, privacy: .public) cannot be offered: \(BundledServiceRuntimes.message(for: error), privacy: .public)"
            )
            return nil
        }
        guard let release else { return nil }
        return Self.offer(release, of: kind, reusesInstalledCopy: await reusesInstalledCopy(release))
    }

    /// The offer of a pinned release of `kind`; nil for another kind or a release without an exact
    /// size.
    package static func offer(
        _ release: RuntimeRelease, of kind: RuntimeKind, reusesInstalledCopy: Bool = false
    ) -> ServiceRuntimeOffer? {
        guard release.kind == kind, let size = release.downloadSize, let host = release.artifact.downloadURL?.host
        else { return nil }
        return ServiceRuntimeOffer(
            name: kind.title, versionLabel: release.versionLabel, downloadSize: size, source: host,
            installedSize: release.installedSize, reusesInstalledCopy: reusesInstalledCopy)
    }
}
