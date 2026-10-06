import Foundation
import JerdWeb

extension SitesModel {
    /// The approval sheet shows this message while the approved setup runs.
    static let approvalMessage = "Applying HTTPS setup. Complete or cancel the macOS approval prompt…"

    /// The state of the HTTPS setup that the page explains, or nil when nothing needs the user.
    public var systemSetupState: SystemSetupState? {
        if runningApprovalID != nil { return .inProgress(Self.approvalMessage) }
        if setup?.hasPendingRecovery == true { return .recoveryPending }
        if let setupReadFailure { return .unreadable(setupReadFailure) }
        if environment.state == .setupRequired { return .approvalRequired }
        return nil
    }

    /// Applies the approved HTTPS setup and continues the waiting change. The work changes the
    /// Mac, so it cannot stop; Cancel only closes the sheet. `runningApprovalID` marks it.
    @discardableResult
    public func approve(_ approval: HTTPSApproval) -> Task<Void, Never>? {
        guard canChange else { return nil }
        approvalFailure = nil
        runningApprovalID = approval.id
        let task = startWork(Self.approvalMessage) { [self] in
            do {
                configuration = try await port.approve(approval)
                operation = .idle
                if sheet?.approval == approval { sheet = nil }
            } catch is CancellationError {
                operation = .idle
            } catch {
                operation = .idle
                reportApprovalFailure(ErrorText.message(for: error), approval: approval)
            }
            runningApprovalID = nil
        }
        if task == nil { runningApprovalID = nil }
        return task
    }

    /// Cancel of the approval sheet.
    public func closeApproval() {
        cancelApproval()
    }

    /// Closes the approval sheet. A waiting change is forgotten; a running approval continues.
    /// - Returns: The task that forgets the waiting change, or nil.
    @discardableResult
    public func cancelApproval() -> Task<Void, Never>? {
        guard let approval = sheet?.approval else { return nil }
        sheet = nil
        approvalFailure = nil
        guard runningApprovalID != approval.id else { return nil }
        let port = port
        return Task { await port.discard(approval) }
    }

    /// Runs the confirmed step and clears the confirmation.
    @discardableResult
    public func confirm() -> Task<Void, Never>? {
        guard let step = confirmation else { return nil }
        confirmation = nil
        switch step {
        case .removeSite(let site):
            return perform(step.workingMessage) { model in
                model.accept(try await model.port.apply(.remove(site.id), startIfStopped: false))
            }
        case .removeSystemSetup:
            return performSystemStep(step) { try await $0.port.removeSystemSetup() }
        case .reconnectHelper:
            return performSystemStep(step) { try await $0.port.reconnectHelper() }
        }
    }

    /// Opens Login Items & Extensions, where the user allows the helper.
    public func openLoginItems() {
        Task { await port.openLoginItems() }
    }

    /// A system setup step. Its failure uses the window alert, because it changed the Mac.
    private func performSystemStep(
        _ step: SitesConfirmation, _ work: @escaping @MainActor (SitesModel) async throws -> Void
    ) -> Task<Void, Never>? {
        startWork(step.workingMessage) { [self] in
            do {
                try await work(self)
            } catch is CancellationError {
            } catch {
                shell.alert(AppAlert(title: "System Setup Did Not Finish", message: ErrorText.message(for: error)))
            }
            operation = .idle
        }
    }

    private func reportApprovalFailure(_ message: String, approval: HTTPSApproval) {
        if sheet?.approval == approval {
            approvalFailure = message
        } else {
            shell.alert(AppAlert(title: "HTTPS Setup Did Not Finish", message: message))
        }
    }
}
