import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdSystem
import JerdUI

/// Recovery records, backups, registrations, and the HTTPS recovery report in memory.
/// A recovered record and a removed item leave the data, like the live services.
public actor InMemoryAdvancedPorts: RecoveryPort, ExecutableRegistrationPort, HTTPSRecoveryPort {
    public var findings: [RecoveryFinding]
    public var backups: [RetainedBackup]
    public var registrationsValue: LocalRuntimeRegistrations
    public var httpsStatus: SystemRecoveryStatus?
    /// When set, every changing call throws this message.
    public var failure: String?
    /// While true, every changing call waits, like a recovery that waits for a graceful stop.
    public var isHeld = false
    public private(set) var calls: [String] = []

    public init(
        findings: [RecoveryFinding] = [], backups: [RetainedBackup] = [],
        registrations: LocalRuntimeRegistrations = LocalRuntimeRegistrations(), httpsStatus: SystemRecoveryStatus? = nil
    ) {
        self.findings = findings
        self.backups = backups
        self.registrationsValue = registrations
        self.httpsStatus = httpsStatus
    }

    public func configure(_ change: @Sendable (isolated InMemoryAdvancedPorts) -> Void) {
        change(self)
    }

    public func inspectProcesses() async -> [RecoveryFinding] { findings }
    public func inspectBackups() async -> [RetainedBackup] { backups }
    public func registrations() async throws -> LocalRuntimeRegistrations { registrationsValue }
    public func pendingRecovery() async throws -> SystemRecoveryStatus? { httpsStatus }

    public func recoverProcess(_ id: String) async throws {
        await waitWhileHeld()
        try record("recover \(id)")
        findings.removeAll { $0.id == id }
    }

    public func removeBackup(_ id: String) async throws {
        try record("remove backup \(id)")
        backups.removeAll { $0.id == id }
    }

    public func importPHP(cli: URL, fpm: URL) async throws {
        try record("import PHP \(cli.path) \(fpm.path)")
    }

    public func importCaddy(_ executable: URL) async throws {
        try record("import Caddy \(executable.path)")
    }

    public func removePHP(_ id: UUID) async throws {
        try record("remove PHP \(id.uuidString)")
        registrationsValue.php.removeAll { $0.id == id }
    }

    public func recover(_ status: SystemRecoveryStatus, action: SystemRecoveryAction) async throws {
        try record("recover HTTPS \(action.rawValue)")
        httpsStatus = nil
    }

    private func waitWhileHeld() async {
        while isHeld, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func record(_ call: String) throws {
        calls.append(call)
        if let failure { throw JerdError.unavailable(failure) }
    }
}
