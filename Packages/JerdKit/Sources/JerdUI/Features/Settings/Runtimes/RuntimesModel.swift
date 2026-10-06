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

    @ObservationIgnored let port: any RuntimeInventory
    @ObservationIgnored var checkTask: Task<Void, Never>?
    @ObservationIgnored var installTask: Task<Void, Never>?

    public init(port: any RuntimeInventory) {
        self.port = port
    }

    /// Reads the installed runtimes. A failure shows on the page; the old values stay.
    public func load() async {
        do {
            inventory = try await port.snapshot()
            if operation.failureMessage != nil { operation = .idle }
        } catch {
            operation = .failed(message: ErrorText.message(for: error))
        }
    }

    /// The release that the picker of `kind` selects.
    public func selectedRelease(_ kind: RuntimeKind) -> RuntimeRelease? {
        checks[kind]?.releases.first { $0.id == selections[kind] }
    }

    /// True when the user can start a check now.
    public var canCheck: Bool { !isChecking && !isShuttingDown }

    /// True when the user can start an installation or change the default PHP now.
    public var canChangeRuntimes: Bool {
        installation == nil && !isShuttingDown && !operation.isWorking
    }

    /// Makes a registered PHP runtime the default.
    @discardableResult
    public func useAsDefault(_ php: RegisteredPHP) -> Task<Void, Never>? {
        guard canChangeRuntimes, inventory.defaultPHPID != php.id else { return nil }
        operation = .working("Changing the default PHP…")
        return Task {
            do {
                try await port.setDefaultPHP(php.id)
                operation = .idle
            } catch {
                operation = .failed(message: ErrorText.message(for: error))
            }
            await load()
        }
    }

    /// Removes the page failure banner.
    public func dismissFailure() {
        if operation.failureMessage != nil { operation = .idle }
    }
}
