import Darwin
import Foundation
import JerdFoundation
import JerdProcess

extension ManagedInstance {
    /// Starts the server. On failure the state is `failed`, or `stuck` when a process stays owned,
    /// and the error keeps the kind of the step that failed.
    public func start() async throws {
        try requireNoLease()
        try requireStartable()
        apply(.startRequested)
        try await performStart(keepLockOnFailure: false)
    }

    func requireStartable() throws {
        guard !state.isBusy else { throw JerdError.unavailable(messages.busy) }
        guard process == nil else { throw JerdError.unavailable(messages.alreadyHasProcess) }
    }

    func performStart(keepLockOnFailure: Bool) async throws {
        do {
            let pid = try await runStartSteps()
            apply(.startSucceeded(pid: pid))
        } catch {
            throw await failStart(error, keepLock: keepLockOnFailure)
        }
    }

    /// The shared start order. A read-only record check comes first, so a process that survived
    /// a crash gives the recovery message and not "port occupied".
    /// The port checks follow, so a conflict creates no file.
    private func runStartSteps() async throws -> pid_t {
        let definition = definition
        let profile = definition.profile
        try effects.startGate.requireNoLiveRecord(profile.record)
        for port in profile.ports { try await effects.ports.requireFree(port) }
        try OwnedDirectory.create(profile.folder, within: profile.containingDirectory)
        let clearance = try clearStart(profile)
        try await definition.versionProbe.verify(using: effects.commands)
        let steps = StartStepRunner(instance: self, clearance: clearance)
        let tools = StartTools(commands: effects.commands, setup: steps, initializer: steps)
        let plan = try await definition.prepareStart(tools)
        let owned = try await removingSecretFiles(of: plan) {
            let owned = try await launch(plan, clearance: clearance)
            try await awaitReadiness(of: owned)
            return owned
        }
        try await definition.completeStart()
        return owned.processID
    }

    /// Takes the lock (or reuses the lease lock) and requires that no earlier process lives.
    private func clearStart(_ profile: ServiceProfile) throws -> StartClearance {
        let held = try lock ?? InstanceLock.acquire(at: profile.record.lockFile, messages: profile.messages.lock)
        lock = held
        return try effects.startGate.requireStopped(profile.record, holding: held)
    }

    /// Launches `plan` and saves its record. The process is owned before the record is saved, so
    /// a failed save leads to the normal failure path, which stops it.
    func launch(_ plan: LaunchPlan, clearance: StartClearance) async throws -> OwnedServiceProcess {
        let profile = definition.profile
        let owned = try await OwnedServiceProcess.launch(
            plan, log: profile.log, processes: effects.processes,
            policy: effects.stopPolicy(signal: profile.stopSignal),
            messages: profile.messages)
        process = owned
        try owned.saveRecord(
            runtimeID: profile.runtimeID, signal: profile.stopSignal, clearance: clearance, recorder: effects.recorder)
        return owned
    }

    /// Polls readiness, then requires exact loopback listener ownership and a live process.
    func awaitReadiness(of owned: OwnedServiceProcess) async throws {
        let check = owned.plan.readiness
        let poller = ReadinessPoller(clock: effects.clock)
        switch try await poller.poll(check, secrets: owned.plan.secrets, isAlive: { await owned.isAlive() }) {
        case .ready:
            break
        case .exited:
            throw JerdError.processFailed("\(messages.exitedBeforeReady) \(logTail(owned))")
        case .timedOut(let lastFailure):
            let detail = check.timeoutDetail == .lastFailure ? lastFailure : logTail(owned)
            throw JerdError.timedOut("\(check.timeoutMessage) \(detail)")
        }
        try await effects.ports.verifyOwnership(pid: owned.processID, expected: owned.plan.ports)
        guard await owned.isAlive() else { throw JerdError.processFailed(messages.exitedDuringCheck) }
    }

    /// Runs `step` (a launch and its readiness check), then removes the secret files of `plan`,
    /// also when the step fails. A failed removal fails the step, or is added to its error.
    func removingSecretFiles<Value: Sendable>(
        of plan: LaunchPlan, during step: () async throws -> Value
    ) async throws -> Value {
        let outcome: Result<Value, any Error>
        do {
            outcome = .success(try await step())
        } catch {
            outcome = .failure(error)
        }
        do {
            try plan.removeSecretFiles()
        } catch {
            guard case .failure(let failure) = outcome else { throw error }
            throw SecretFiles.combine(error, after: failure)
        }
        return try outcome.get()
    }

    /// Stops what the start left behind and sets `failed` or `stuck`.
    private func failStart(_ error: any Error, keepLock: Bool) async -> JerdError {
        let kind = (error as? JerdError)?.kind ?? .processFailed
        var detail = FailureDetail.describe(error)
        if let owned = process, !(error is RetainedProcessError) {
            let result = await stopOwned(owned, keepLock: keepLock, intent: .startStep)
            if let message = result.failureMessage { detail += " " + message }
        }
        if let owned = process {
            apply(.startFailedKeepingProcess(pid: owned.processID, reason: detail))
        } else {
            if !keepLock { releaseLockIfIdle() }
            apply(.startFailed(reason: detail))
        }
        return JerdError(kind, detail)
    }

    /// Runs one setup phase (see `SetupPhaseRunning`) inside the current start.
    func runSetupPhase(_ plan: LaunchPlan, clearance: StartClearance) async throws {
        guard state == .starting else { throw JerdError.unavailable(messages.busy) }
        let owned = try await removingSecretFiles(of: plan) {
            let owned = try await launch(plan, clearance: clearance)
            try await awaitReadiness(of: owned)
            return owned
        }
        let result = await stopOwned(owned, keepLock: true, intent: .startStep)
        if let message = result.failureMessage { throw RetainedProcessError(message: message) }
    }
}
