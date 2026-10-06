extension AppState {
    /// Starts Jerd once, independent of any window: applies the Dock and icon choices, loads
    /// every feature and settings page, starts the updater, and starts polling. The app
    /// delegate calls it from `applicationDidFinishLaunching`. A second call waits for the first.
    /// A quit that starts during the launch waits for the feature that launches now; the
    /// features after it do not launch.
    public func launch() async {
        if launchTask == nil {
            appearance.apply()
            appUpdates.start()
            launchTask = Task { await continueLaunch() }
        }
        await launchTask?.value
    }

    /// Launches the features that did not launch yet, then loads the settings pages and starts
    /// polling. Stops before each step while a quit runs; a cancelled quit calls it again.
    func continueLaunch() async {
        for feature in features where !launchedSections.contains(feature.section) {
            guard !shutdown.isQuitting else { return }
            await feature.launch()
            launchedSections.insert(feature.section)
        }
        guard !shutdown.isQuitting else { return }
        await runtimes.load()
        await advanced.load()
        guard !shutdown.isQuitting else { return }
        for poller in pollers {
            poller.start(activity: activity)
        }
        isLaunched = true
    }

    /// The user opened Jerd again, for example from Applications or the Dock. This is the way
    /// back when both the menu bar icon and the Dock icon are off.
    public func reopen() {
        windows.showMainWindow()
    }

    /// Answers one quit request. The first request starts the staged quit and replies once
    /// through `reply`; a request during a running quit is cancelled at once. The quit state
    /// changes before this function returns, so two requests in one turn start one quit.
    /// - Parameter reply: Receives true when every service stopped, false when the quit is cancelled.
    public func requestTermination(reply: @escaping @MainActor (Bool) -> Void) -> TerminationReply {
        let decision = shutdown.replyToNewRequest
        guard decision == .later else { return decision }
        let launch = launchTask
        guard
            let quit = shutdown.start(
                after: { await launch?.value }, participants: { [weak self] in self?.shutdownParticipants ?? [] })
        else { return .cancel }
        appUpdates.isTerminating = true
        Task {
            let outcome = await quit.value
            finishTermination(outcome)
            reply(outcome == .stopped)
        }
        return .later
    }

    /// Every participant of the staged quit; the coordinator sorts them by phase. A feature
    /// takes part only after its launch finished, so `shutdown()` never comes before `launch()`.
    var shutdownParticipants: [any ShutdownParticipant] {
        let launched = features.filter { launchedSections.contains($0.section) }
        return [operationLock, runtimes] + launched.flatMap(\.shutdownParticipants)
    }

    private func finishTermination(_ outcome: ShutdownOutcome) {
        switch outcome {
        case .stopped:
            for poller in pollers {
                poller.stop()
            }
        case .cancelled(_, let message, let destination):
            appUpdates.isTerminating = false
            open(destination)
            alert = .quitCancelled(message)
            if launchTask != nil, !isLaunched {
                launchTask = Task { await continueLaunch() }
            }
        }
    }
}
