import Foundation
import JerdFoundation
import JerdWeb

extension SitesModel {
    /// The IDs of the enabled sites, in configuration order.
    public var enabledSiteIDs: [UUID] {
        configuration.sites.filter(\.isEnabled).map(\.id)
    }

    /// True when an enabled site is not served.
    public var hasStoppedEnabledSite: Bool {
        enabledSiteIDs.contains { !environment.siteIDs.contains($0) }
    }

    /// True while sites run or site work runs, so Stop All Sites has something to stop.
    public var showsStopAll: Bool {
        !environment.siteIDs.isEmpty || operation.isWorking || environment.state == .starting
    }

    /// True when the All Sites row of a site page shows Stop All Sites. While stoppable work
    /// runs, the operation banner owns that button, so the page never shows it twice.
    public var showsStopAllOnPage: Bool {
        showsStopAll && !(operation.isWorking && canStopAll)
    }

    /// True when Stop All Sites can run now. Work that changes the Mac (an HTTPS approval, a
    /// system setup step, a removal) cannot end at a next step, so Stop waits until it ends.
    public var canStopAll: Bool {
        !isShuttingDown && showsStopAll && !isRunningUnstoppableWork
    }

    /// True while work runs that the user cannot stop: the flag of the operation says so.
    var isRunningUnstoppableWork: Bool {
        if case .working(_, canStop: false) = operation { return true }
        return false
    }

    /// True when the approved HTTPS setup covers the site's hostname for this installation's
    /// CA, the same rule as the site transaction. Its Start then needs no approval sheet.
    public func isApproved(_ site: Site) -> Bool {
        setup.map { ApprovalPredicate.approves($0, hostnames: [site.hostname], authority: authority) } ?? false
    }

    /// Serves every enabled site.
    @discardableResult
    public func startAll() -> Task<Void, Never>? {
        let ids = Set(enabledSiteIDs)
        return perform("Checking PHP-FPM and HTTPS…", canStop: true) { model in
            try model.requireStartable(ids)
            model.accept(try await model.port.run(ids))
        }
    }

    /// Adds one site to the served sites.
    @discardableResult
    public func start(_ site: Site) -> Task<Void, Never>? {
        let ids = environment.siteIDs.union([site.id])
        return perform("Starting \(site.displayName)…", canStop: true) { model in
            try model.requireStartable(ids)
            model.accept(try await model.port.run(ids))
        }
    }

    /// Removes one site from the served sites. The last site stops PHP-FPM and Caddy.
    @discardableResult
    public func stop(_ site: Site) -> Task<Void, Never>? {
        let ids = environment.siteIDs.subtracting([site.id])
        return perform("Stopping \(site.displayName)…", canStop: true) { model in
            model.accept(try await model.port.run(ids))
        }
    }

    /// Stops every site. Running site work ends at its next step first, so a slow start never
    /// blocks Stop. The stop waits for other work that holds the shared lock.
    @discardableResult
    public func stopAll() -> Task<Void, Never>? {
        guard canStopAll else { return nil }
        let running = currentWork
        let wasWorking = operation.isWorking
        if wasWorking {
            operation = .working(message: "Stopping sites…", canStop: false)
        }
        return Task {
            if wasWorking {
                await port.requestStop()
                await running?.value
            }
            await stopEnvironmentWhenFree()
        }
    }

    /// Stops PHP-FPM and Caddy as soon as the shared lock is free.
    private func stopEnvironmentWhenFree() async {
        do {
            try await lock.runWhenFree("Stopping PHP-FPM and Caddy…") { [self] in
                operation = .working("Stopping PHP-FPM and Caddy…")
                do {
                    try await port.stopEnvironment()
                    operation = .idle
                } catch {
                    operation = .failed(message: ErrorText.message(for: error))
                }
                await settle()
            }
        } catch {
            // A quit closed the lock first. The quit stops PHP-FPM and Caddy itself.
            if operation.isWorking { operation = .idle }
        }
    }

    /// The start rules that the page can check before any work: at least one enabled site,
    /// only enabled sites, and a Caddy executable.
    func requireStartable(_ ids: Set<UUID>) throws {
        guard !enabledSiteIDs.isEmpty, !ids.isEmpty else {
            throw JerdError.invalid("Enable at least one registered site.")
        }
        guard ids.isSubset(of: Set(enabledSiteIDs)) else {
            throw JerdError.invalid("The selected sites changed or are disabled. Select the sites again.")
        }
        guard configuration.caddy != nil else {
            throw JerdError.unavailable("Caddy is unavailable. Install Caddy in Runtimes, or select it in Advanced.")
        }
    }
}
