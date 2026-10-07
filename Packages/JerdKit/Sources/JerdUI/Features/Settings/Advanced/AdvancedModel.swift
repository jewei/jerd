import Foundation
import JerdProcess
import JerdServiceKit
import JerdSystem
import Observation

/// Dashboard › Advanced: HTTPS setup recovery, process recovery, retained backups, local
/// executables, and PHP registrations. One operation runs at a time; each destructive step
/// waits for an explicit confirmation.
@MainActor
@Observable
public final class AdvancedModel {
    public internal(set) var findings: [RecoveryFinding] = []
    public internal(set) var backups: [RetainedBackup] = []
    public internal(set) var httpsRecovery: SystemRecoveryStatus?
    /// True after the first inspection, so empty sections can say that nothing was found.
    public internal(set) var hasInspected = false
    public internal(set) var operation: OperationState = .idle
    /// The step that waits for confirmation. The page shows it as a dialog.
    public var confirmation: AdvancedConfirmation?

    @ObservationIgnored let recovery: any RecoveryPort
    @ObservationIgnored let executables: any ExecutableRegistrationPort
    @ObservationIgnored let https: any HTTPSRecoveryPort
    @ObservationIgnored let panels: any FilePanelPresenting
    @ObservationIgnored let workspace: any WorkspaceOpening
    /// The shared lock: every step of this page holds it, so it never runs at the same time as
    /// site work, a runtime activation, or the default PHP change, and the quit waits for it.
    @ObservationIgnored let lock: OperationLock
    /// The registrations, shared with Runtimes and the dashboard.
    public let registry: RegistrationStore

    public init(
        recovery: any RecoveryPort, executables: any ExecutableRegistrationPort, https: any HTTPSRecoveryPort,
        panels: any FilePanelPresenting, workspace: any WorkspaceOpening, registry: RegistrationStore? = nil,
        lock: OperationLock = OperationLock()
    ) {
        self.lock = lock
        self.registry = registry ?? RegistrationStore(port: executables)
        self.recovery = recovery
        self.executables = executables
        self.https = https
        self.panels = panels
        self.workspace = workspace
    }

    /// The PHP and Caddy registrations, from the shared store.
    public var registrations: LocalRuntimeRegistrations { registry.registrations }

    /// True when a step can start: no work holds the shared lock and no quit runs.
    public var isIdle: Bool { lock.isFree }

    /// Reads the registrations and the HTTPS recovery report. Records and backups wait for
    /// the user's inspection, because an inspection reads every saved service record. The
    /// page calls it each time it appears.
    public func load() async {
        do {
            try await registry.reload()
            httpsRecovery = try await https.pendingRecovery()
        } catch {
            operation = .failed(message: ErrorText.message(for: error))
        }
    }

    /// Inspects saved service records and retained backups.
    @discardableResult
    public func inspect() -> Task<Void, Never>? {
        perform("Inspecting saved service records and backups…") { model in
            model.findings = await model.recovery.inspectProcesses()
            model.backups = await model.recovery.inspectBackups()
            model.hasInspected = true
        }
    }

    /// Runs the confirmed step and clears the confirmation.
    @discardableResult
    public func confirm() -> Task<Void, Never>? {
        guard let step = confirmation else { return nil }
        confirmation = nil
        return perform(step.workingMessage) { model in
            try await model.run(step)
        }
    }

    /// Shows a backup folder in Finder.
    public func reveal(_ backup: RetainedBackup) {
        workspace.reveal(backup.directory)
    }

    /// Removes the failure banner.
    public func dismissFailure() {
        if operation.failureMessage != nil { operation = .idle }
    }

    /// Runs one operation with its banner message. A failure shows once, on this page.
    func perform(
        _ message: String, _ work: @escaping @MainActor (AdvancedModel) async throws -> Void
    ) -> Task<Void, Never>? {
        guard isIdle else { return nil }
        operation = .working(message)
        return lock.run(message) { [self] in
            do {
                try await work(self)
                operation = .idle
            } catch {
                operation = .failed(message: ErrorText.message(for: error))
            }
        }
    }
}
