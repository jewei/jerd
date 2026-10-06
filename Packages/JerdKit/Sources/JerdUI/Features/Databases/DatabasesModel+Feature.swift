import JerdDatabases
import JerdDesign
import JerdServiceKit

extension DatabasesModel: WorkspaceFeature, ShutdownParticipant {
    public var section: AppSection { .databases }
    public var shutdownPhase: ShutdownPhase { .databases }
    public var pollingPolicy: PollingPolicy { .services }
    public var shutdownParticipants: [any ShutdownParticipant] { [self] }
    public var bannerActivity: BannerActivity? { nil }

    /// File › New Database… (⌘N): the Add sheet with the first installed engine. The sheet
    /// can switch the engine. It is off while a sheet shows, so it never replaces a draft.
    public var newItemAction: FeatureAction? {
        FeatureAction(id: "databases.new", title: "New Database…", isEnabled: canAdd && sheet == nil) { [weak self] in
            guard let self, let engine = availableEngines.first else { return }
            beginAdd(engine)
        }
    }

    /// The card status: a problem first, then work, then the running count.
    public var status: DisplayStatus {
        if loadState.failureMessage != nil { return DisplayStatus("Not loaded", tone: .failed) }
        let states = services.map { state(of: $0.id) }
        if states.contains(where: { if case .failed = $0 { true } else { false } }) {
            return DisplayStatus("Failed", tone: .failed)
        }
        if states.contains(where: { if case .stuck = $0 { true } else { false } }) {
            return DisplayStatus("Did not stop", tone: .attention)
        }
        if isBusy || states.contains(where: \.isBusy) { return DisplayStatus("Working…", tone: .busy) }
        if services.isEmpty { return DisplayStatus("No services", tone: .idle) }
        let running = states.filter(\.isRunning).count
        return running > 0
            ? DisplayStatus("\(running) of \(services.count) running", tone: .ready)
            : DisplayStatus("Stopped", tone: .idle)
    }

    public var summary: FeatureSummary {
        guard !services.isEmpty else {
            let add = FeatureAction(id: "databases.add", title: "Add Database…", isEnabled: canAdd, isPrimary: canAdd) {
                [weak self] in
                guard let self, let engine = availableEngines.first else { return }
                navigate?(.section(.databases))
                beginAdd(engine)
            }
            return FeatureSummary(status: status, summary: "Add MySQL, PostgreSQL, or Redis services.", actions: [add])
        }
        return FeatureSummary(
            status: status, summary: services.map(\.name).joined(separator: ", "), actions: cardActions)
    }

    /// Start or Stop for each service, as in the menu bar. The first service that can start is
    /// the next step; Stop is never the next step. A narrow card keeps the next step as a button
    /// and moves the others into its More menu.
    private var cardActions: [FeatureAction] {
        let next = services.first { canStart($0.id) }?.id
        return services.map { controlAction(for: $0, isPrimary: $0.id == next) }
    }

    public var menuItems: [MenuBarItem] {
        guard !services.isEmpty else { return [] }
        let items = services.map { MenuBarItem.action(controlAction(for: $0, isPrimary: false)) }
        return [.submenu("Databases", id: "databases.menu", items: items)]
    }

    /// Stop for a service that runs or did not stop, else Start.
    private func controlAction(for service: DatabaseService, isPrimary: Bool) -> FeatureAction {
        if state(of: service.id).offersStop {
            return FeatureAction(
                id: "databases.stop.\(service.id)", title: "Stop \(service.name)", isEnabled: canStop(service.id)
            ) { [weak self] in self?.stop(service.id) }
        }
        return FeatureAction(
            id: "databases.start.\(service.id)", title: "Start \(service.name)", isEnabled: canStart(service.id),
            isPrimary: isPrimary
        ) { [weak self] in self?.start(service.id) }
    }

    public func launch() async {
        await load()
    }

    /// Waits for running work, then stops every service in parallel. False keeps Jerd open.
    public func shutdown() async -> Bool {
        isShuttingDown = true
        await running.waitForAll()
        guard loadState.isLoaded, !services.isEmpty else { return true }
        do {
            try await port.stopAll()
            await refresh()
            return true
        } catch {
            await refresh()
            operation = .failed(message: ErrorText.message(for: error))
            return false
        }
    }

    public func resumeAfterCancelledQuit() {
        isShuttingDown = false
    }
}
