import Darwin
import Foundation
import JerdFoundation
import JerdProcess

extension EngineRunner {
    public func start(
        _ plan: ServingPlan, layout: RunLayout, binding: ListenerBinding, listeners: InheritedListeners?
    ) async throws -> EngineRunID {
        try Task.checkCancellation()
        guard run == nil, gate.tryEnter() else { throw JerdError.processFailed("The engine is already active.") }
        defer { gate.leave() }
        guard !plan.isEmpty, plan.sites.allSatisfy(\.site.isEnabled) else {
            throw JerdError.invalid("Enable the sites before starting them.")
        }
        guard plan.siteIDs.count == plan.sites.count else {
            throw JerdError.invalid("The serving plan contains a duplicate site ID.")
        }
        let epoch = stopEpoch
        state = .starting
        run = ActiveRun(layout: layout)
        do {
            let startPlan = try await prepare(
                plan, layout: layout, binding: binding, listeners: listeners, epoch: epoch)
            try await launch(startPlan, listeners: listeners, epoch: epoch)
            return try await confirm(startPlan, epoch: epoch)
        } catch {
            let survivor = await stopOwned()
            let failure = error is CancellationError ? nil : FailureDetail.describe(error)
            state = Self.stoppedState(failure: failure, survivor: survivor)
            throw error
        }
    }

    /// Checks, locks, inspects, writes, and validates everything before the first launch.
    private func prepare(
        _ plan: ServingPlan, layout: RunLayout, binding: ListenerBinding, listeners: InheritedListeners?,
        epoch: UInt64
    ) async throws -> EngineStartPlan {
        guard geteuid() != 0 else { throw JerdError.processFailed("The serving engine cannot run as root.") }
        let sites = try SiteValidator().revalidate(plan.sites.map(\.site))
        try await requireListeners(binding, listeners)
        guard FileProbe.presence(at: layout.socketDirectory) == .absent else {
            throw JerdError.processFailed(
                "The socket directory already exists. Use a new private run directory; do not remove an unknown socket."
            )
        }
        let records = records(layout)
        let lock = try records.lock()
        run?.lock = lock
        try records.clearPrevious(holding: lock)
        try LegacyPoolFiles.remove(from: layout.environment)
        let startPlan = try EngineStartPlan(plan: plan, validatedSites: sites, layout: layout, binding: binding)
        try EngineFiles.createFolders(startPlan)
        try OwnedDirectory.create(layout.socketDirectory)
        run?.ownsSocketDirectory = true
        try await requireUnchanged(startPlan)
        try checkpoint(epoch)
        try await writeAndValidate(startPlan, listeners: listeners, epoch: epoch)
        return startPlan
    }

    private func requireListeners(_ binding: ListenerBinding, _ listeners: InheritedListeners?) async throws {
        if let listeners {
            let ports = try ListenerPorts.read(listeners)
            guard binding.inherited, ports.http == binding.httpPort, ports.https == binding.httpsPort else {
                throw JerdError.invalid("Listener ports do not match the engine request.")
            }
        } else {
            guard !binding.inherited else { throw JerdError.invalid("Listener ports do not match the engine request.") }
            try await services.ports.requireFree(binding.httpsPort)
            try await services.ports.requireFree(binding.httpPort)
        }
    }

    func requireUnchanged(_ plan: EngineStartPlan) async throws {
        let work = plan.layout.environment.configurationDirectory
        for pool in plan.pools { try await services.drift.requireUnchanged(pool.runtime, workDirectory: work) }
        try await services.drift.requireUnchanged(plan.caddy, workDirectory: work)
    }

    /// Writes the pool files and `caddy.json`, runs every validation, then adds the PHP CA bundle.
    private func writeAndValidate(
        _ plan: EngineStartPlan, listeners: InheritedListeners?, epoch: UInt64
    ) async throws {
        for pool in plan.pools { try EngineFiles.writePool(pool, caBundle: nil) }
        try EngineFiles.writeCaddy(plan)
        for pool in plan.pools { try await validate(plan.fpmTest(pool)) }
        try checkpoint(epoch)
        try await validate(plan.caddyValidation(listeners))
        let environment = plan.layout.environment
        if let bundle = try services.caBundle.prepare(
            rootCertificate: plan.layout.rootCertificateFile, installationID: plan.layout.authority.installationID,
            output: environment.phpCABundleFile)
        {
            for pool in plan.pools { try EngineFiles.writePool(pool, caBundle: bundle) }
        }
        try checkpoint(epoch)
    }

    /// Runs one validation command. A non-zero status shows the command's diagnostics.
    func validate(_ request: ProcessRequest) async throws {
        let result = try await services.commands.run(request, timeout: services.timings.validationTimeout)
        guard result.succeeded else {
            throw JerdError.processFailed("Configuration validation failed: \(result.diagnosticOutput)")
        }
    }

    func records(_ layout: RunLayout) -> WebProcessRecords {
        WebProcessRecords(environment: layout.environment, gate: services.startGate, recorder: services.recorder)
    }
}
