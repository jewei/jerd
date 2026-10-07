import Foundation
import JerdDatabases
import JerdRuntimes

extension DatabasesModel {
    /// True when a runtime installation can start now: one at a time, and not during a quit.
    public var canInstallRuntime: Bool {
        loadState.isLoaded && runtimeInstallation == nil && !isShuttingDown && !editorOperation.isWorking
            && runtimeInstallElsewhere?() == nil
    }

    /// Asks to confirm the download of an engine that has no runtime yet.
    public func requestRuntimeInstall(_ engine: DatabaseEngine) {
        guard canInstallRuntime, let offer = offer(for: engine) else { return }
        pendingRuntimeInstall = offer
    }

    /// Installs the confirmed engine. The page shows the progress; Cancel stops it.
    @discardableResult
    public func confirmRuntimeInstall() -> Task<Void, Never>? {
        guard let offer = pendingRuntimeInstall else { return nil }
        pendingRuntimeInstall = nil
        guard canInstallRuntime else { return nil }
        let task = track { [self] in
            do {
                _ = try await installRuntime(offer, addsService: false)
            } catch is CancellationError {
                runtimeNotice = DatabaseRuntimeNotice(
                    engine: offer.engine, message: DatabaseRuntimeCopy.cancelled(offer), isFailure: false)
            } catch {
                runtimeNotice = DatabaseRuntimeNotice(
                    engine: offer.engine, message: ErrorText.message(for: error), isFailure: true)
            }
        }
        runtimeInstallTask = task
        return task
    }

    /// Stops the running installation before its final rename. Nothing is installed then.
    public func cancelRuntimeInstall() {
        guard let installation = runtimeInstallation else { return }
        if installation.addsService {
            editorTask?.cancel()
        } else {
            runtimeInstallTask?.cancel()
        }
    }

    public func dismissRuntimeNotice() {
        runtimeNotice = nil
    }

    /// The one installation step of the page and of Add Database: download, verify, install,
    /// and register, then read the new runtime. It throws `CancellationError` after a cancel.
    func installRuntime(_ offer: DatabaseRuntimeOffer, addsService: Bool) async throws -> DatabaseRuntime {
        runtimeNotice = nil
        runtimeInstallation = DatabaseRuntimeInstallation(offer: offer, addsService: addsService)
        defer { runtimeInstallation = nil }
        let engine = offer.engine
        do {
            let runtime = try await port.installRuntime(engine) { [weak self] progress in
                Task { @MainActor in self?.show(progress, for: engine) }
            }
            await refresh()
            return runtime
        } catch {
            await refresh()
            // A cancelled task can end with any error of the step that it stopped.
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    /// Progress that arrives after the installation ended is dropped.
    private func show(_ progress: RuntimeInstallProgress, for engine: DatabaseEngine) {
        guard runtimeInstallation?.engine == engine else { return }
        runtimeInstallation?.progress = progress
    }
}
