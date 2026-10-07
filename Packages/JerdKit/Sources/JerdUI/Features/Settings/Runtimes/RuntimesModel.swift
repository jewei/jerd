import Foundation
import JerdManifest
import JerdRuntimes
import Observation

/// Dashboard › Runtimes: installed versions, catalog checks, one installation at a time, and
/// the default PHP. It depends only on the `RuntimeInventory` port, never on other models.
@MainActor
@Observable
public final class RuntimesModel {
    /// The most catalog sources that one check reads at the same time.
    static let checkConcurrency = 3

    public internal(set) var inventory = RuntimeInventorySnapshot()
    public internal(set) var checks: [RuntimeKind: RuntimeUpdateCheck] = [:]
    /// The release ID that the picker of each kind selects.
    public var selections: [RuntimeKind: String] = [:]
    public internal(set) var isChecking = false
    public internal(set) var installation: RuntimeInstallation?
    /// The result of the last installation of each kind.
    public internal(set) var messages: [RuntimeKind: String] = [:]
    public internal(set) var errors: [RuntimeKind: String] = [:]
    /// Page-level work and failures: loading and the default PHP change.
    public internal(set) var operation: OperationState = .idle
    public internal(set) var isShuttingDown = false
    /// The pinned release that waits for the install confirmation (a database engine on demand).
    public var pendingOnDemandInstall: RuntimeRelease?
    /// The runtime that the Databases page installs now, or nil. `AppState` sets it.
    @ObservationIgnored public var runtimeInstallElsewhere: (@MainActor () -> String?)?

    @ObservationIgnored let port: any RuntimeInventory
    /// The registered PHP runtimes and the default PHP, shared with Advanced and the dashboard.
    public let registry: RegistrationStore
    /// The shared lock: the default PHP change and each activation hold it.
    @ObservationIgnored let lock: OperationLock
    @ObservationIgnored var checkTask: Task<Void, Never>?
    @ObservationIgnored var installTask: Task<Void, Never>?
    /// The default PHP change. The quit waits for it.
    @ObservationIgnored var defaultTask: Task<Void, Never>?

    public init(port: any RuntimeInventory, registry: RegistrationStore, lock: OperationLock = OperationLock()) {
        self.port = port
        self.registry = registry
        self.lock = lock
    }

    /// Reads the installed runtimes and the registrations. A failure shows on the page; the
    /// old values stay. The page calls it each time it appears.
    public func load() async {
        do {
            inventory = try await port.snapshot()
            try await registry.reload()
            if operation.failureMessage != nil { operation = .idle }
        } catch {
            operation = .failed(message: ErrorText.message(for: error))
        }
    }

    /// The registered PHP runtimes, in configuration order, with their managed build digest.
    public var registeredPHP: [RegisteredPHP] {
        registry.registrations.php.map { runtime in
            RegisteredPHP(id: runtime.id, version: runtime.version, buildDigest: inventory.phpBuildDigests[runtime.id])
        }
    }

    public var defaultPHPID: UUID? { registry.registrations.defaultPHPID }

    /// The release that the picker of `kind` selects.
    public func selectedRelease(_ kind: RuntimeKind) -> RuntimeRelease? {
        checks[kind]?.releases.first { $0.id == selections[kind] }
    }

    /// True when the user can start a check now.
    public var canCheck: Bool { !isChecking && !isShuttingDown }

    /// True when the user can start an installation or change the default PHP now: no
    /// installation runs, and no other work holds the shared lock.
    public var canChangeRuntimes: Bool {
        installation == nil && !isShuttingDown && !operation.isWorking && lock.isFree
    }

    /// True when an install can start now. The installer is shared with the Databases page, so an
    /// install also waits for a database download there; the default PHP change does not.
    public var canInstallRuntimes: Bool {
        canChangeRuntimes && runtimeInstallElsewhere?() == nil
    }

    /// True when installing `release` reuses a copy on this Mac, so nothing is downloaded.
    public func reusesInstalledCopy(_ release: RuntimeRelease?) -> Bool {
        release.map { inventory.reusableOnDemand.contains($0.kind) } ?? false
    }

    /// Asks to confirm the download of a pinned release, as the Databases page does.
    public func requestOnDemandInstall(_ release: RuntimeRelease) {
        guard canInstallRuntimes, inventory.installableRelease(release.kind) == release else { return }
        pendingOnDemandInstall = release
    }

    /// Installs the confirmed pinned release.
    @discardableResult
    public func confirmOnDemandInstall() -> Task<Void, Never>? {
        guard let release = pendingOnDemandInstall else { return nil }
        pendingOnDemandInstall = nil
        return install(release)
    }

    /// Makes a registered PHP runtime the default.
    @discardableResult
    public func useAsDefault(_ php: RegisteredPHP) -> Task<Void, Never>? {
        guard canChangeRuntimes, defaultPHPID != php.id else { return nil }
        let message = "Changing the default PHP…"
        operation = .working(message)
        let task = lock.run(message) { [self] in
            var failure: String?
            do {
                try await registry.setDefaultPHP(php.id)
            } catch {
                failure = ErrorText.message(for: error)
            }
            await load()
            if let failure {
                operation = .failed(message: failure)
            } else if operation.isWorking {
                operation = .idle
            }
        }
        defaultTask = task
        return task
    }

    /// Removes the page failure banner.
    public func dismissFailure() {
        if operation.failureMessage != nil { operation = .idle }
    }
}
