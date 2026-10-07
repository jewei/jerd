import Foundation
import JerdFoundation
import JerdMail
import JerdManifest
import JerdRuntimes
import JerdUI
import os

/// Installs the pinned Mailpit on demand, then registers it with the mail manager.
///
/// It adds no pipeline of its own: `OnDemandInstallFlow` reuses an earlier copy (also the Mailpit
/// that an earlier Jerd embedded, in `mail-runtimes/`) or lets the one `RuntimeInstaller` of the app
/// download, verify, prepare, and install the pin in `runtime-updates/`, as for RustFS and the
/// database engines. Mailpit needs no preparation tools. Registration only adds the runtime record
/// and chooses the ports: the inbox and its messages are never read or changed, and an existing
/// runtime record is never replaced.
package struct MailRuntimeInstaller: Sendable {
    static let log = Logger(subsystem: "dev.jerd.app", category: "mail-runtimes")

    let flow: OnDemandInstallFlow
    let manager: any MailManaging

    package init(flow: OnDemandInstallFlow, manager: any MailManaging) {
        self.flow = flow
        self.manager = manager
    }

    /// The pinned Mailpit, and whether its install reuses a copy on this Mac. A missing or bad
    /// catalog offers nothing and is logged; the page then leads to Runtimes.
    package func offer() async -> ServiceRuntimeOffer? {
        await flow.offer(of: .mailpit, log: Self.log)
    }

    /// Installs and registers the pinned Mailpit through the one flow.
    package func install(
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> MailRuntime {
        guard let release = try flow.release(of: .mailpit) else {
            throw JerdError.unavailable("This copy of Jerd cannot install Mailpit. Install it in Runtimes.")
        }
        return try await install(release, progress: progress)
    }

    /// Installs and registers the pinned Mailpit release, also for Runtimes › Install….
    package func install(
        _ release: RuntimeRelease, progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> MailRuntime {
        guard release.kind == .mailpit else { throw JerdError.invalid("\(release.kind.title) is not Mailpit.") }
        let runtime: MailRuntime
        switch try await flow.install(release, progress: progress) {
        case .reused(let payload):
            runtime = MailRuntime(id: payload.id, version: payload.version, path: payload.directory.path)
        case .built(let build):
            runtime = RuntimeActivator.mailRuntime(build)
        }
        try await manager.registerRuntime(runtime)
        return runtime
    }

    /// The offer of the pinned Mailpit release; nil for another kind or a release without an exact size.
    package static func offer(_ release: RuntimeRelease, reusesInstalledCopy: Bool = false) -> ServiceRuntimeOffer? {
        OnDemandInstallFlow.offer(release, of: .mailpit, reusesInstalledCopy: reusesInstalledCopy)
    }
}

extension MailRuntimeInstaller {
    /// The live installer: the pinned releases of the app bundle, its one `RuntimeInstaller`, and the
    /// mail manager.
    package init(domain: LiveDomain) {
        self.init(
            flow: OnDemandInstallFlow(
                releases: domain.onDemandRuntimes, installer: domain.runtimeInstaller, layout: domain.layout),
            manager: domain.mail)
    }
}
