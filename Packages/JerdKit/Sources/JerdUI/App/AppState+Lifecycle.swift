extension AppState {
    /// Starts Jerd once, independent of any window: applies the Dock and icon choices, loads
    /// every feature and settings page, starts the updater, and starts polling. The app
    /// delegate calls it from `applicationDidFinishLaunching`.
    public func launch() async {
        guard !hasStartedLaunch else { return }
        hasStartedLaunch = true
        appearance.apply()
        appUpdates.start()
        for feature in features {
            await feature.launch()
        }
        await runtimes.load()
        await advanced.load()
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
    /// through `reply`; a request during a running quit is cancelled at once.
    /// - Parameter reply: Receives true when every service stopped, false when the quit is cancelled.
    public func requestTermination(reply: @escaping @MainActor (Bool) -> Void) -> TerminationReply {
        let decision = shutdown.replyToNewRequest
        guard decision == .later else { return decision }
        appUpdates.isTerminating = true
        Task {
            let outcome = await shutdown.run(shutdownParticipants)
            finishTermination(outcome)
            reply(outcome == .stopped)
        }
        return .later
    }

    /// Every participant of the staged quit; the coordinator sorts them by phase.
    var shutdownParticipants: [any ShutdownParticipant] {
        [runtimes] + features.flatMap(\.shutdownParticipants)
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
        }
    }
}
