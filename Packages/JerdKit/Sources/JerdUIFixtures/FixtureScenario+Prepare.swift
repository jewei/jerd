import JerdDatabases
import JerdManifest
import JerdUI

extension FixtureScenario {
    /// Launches the state and runs the extra steps of the scenario.
    @MainActor
    public func prepare(_ fixture: AppFixture) async {
        let state = fixture.state
        if self == .quitting {
            await fixture.services.storage.configure { $0.stopBehavior = .suspend }
        }
        if self == .runtimesWaiting {
            let progress = ServiceScenario.progress(of: 0, fraction: 0.42)
            await fixture.services.databases.configure {
                $0.configuration = DatabaseConfiguration(runtimes: [SampleServices.embeddedRedis])
                $0.offers = SampleServices.offers
                $0.installBehavior = .suspend(progress)
            }
        }
        await state.launch()
        switch self {
        case .runtimesWaiting:
            state.databases.requestRuntimeInstall(.mysql)
            state.databases.confirmRuntimeInstall()
        case .runtimesChecked:
            await state.runtimes.check()?.value
            if let release = state.runtimes.selectedRelease(.mailpit) {
                state.runtimes.install(release)
            }
        case .advanced:
            await state.advanced.inspect()?.value
        case .quitting:
            _ = state.requestTermination { _ in }
        case .aboutUpdateError:
            fixture.updater.send(.checkStarted)
            fixture.updater.send(
                .cycleFinished(
                    lastCheck: SampleData.now,
                    result: .failed("The update feed could not be read. Check your network connection.")))
        default:
            await prepareSites(fixture)
        }
    }

    /// True when the state shows what the scenario promises.
    @MainActor
    public func isReady(_ fixture: AppFixture) -> Bool {
        let state = fixture.state
        guard state.isLaunched else { return false }
        switch self {
        case .runtimesChecked: return state.runtimes.installation?.progress != nil
        case .runtimesWaiting: return state.databases.runtimeInstallation?.progress != nil
        case .advanced: return state.advanced.hasInspected
        case .quitting: return state.shutdown.message == ShutdownPhase.storage.message
        default: return isSitesReady(fixture)
        }
    }
}
