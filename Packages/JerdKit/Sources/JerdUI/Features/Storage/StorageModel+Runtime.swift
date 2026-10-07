import Foundation
import JerdRuntimes
import JerdStorage

extension StorageModel {
    /// True when the RustFS installation can start now: no runtime yet, a pinned offer, no other
    /// storage work, no installation on another page, and not during a quit.
    public var canInstallRuntime: Bool {
        canChange && !hasRuntime && runtimeOffer != nil && runtimeInstallElsewhere?() == nil
    }

    /// Asks to confirm the installation of the pinned RustFS. Nothing downloads before the user
    /// confirms. The request shows on the Storage page, so a card or menu request shows that page.
    /// - Parameter startsStorage: True for Start: storage starts after the installation.
    public func requestRuntimeInstall(startsStorage: Bool = false) {
        guard canInstallRuntime, let runtimeOffer else { return }
        pendingRuntimeInstall = StorageRuntimeRequest(offer: runtimeOffer, startsStorage: startsStorage)
        presentPage?()
    }

    /// Installs the confirmed RustFS, then starts storage when Start asked for it. The page shows
    /// the progress; Cancel stops it.
    @discardableResult
    public func confirmRuntimeInstall() -> Task<Void, Never>? {
        guard let request = pendingRuntimeInstall else { return nil }
        pendingRuntimeInstall = nil
        guard canInstallRuntime else { return nil }
        let task = running.run { [self] in
            do {
                try await installRuntime(request)
            } catch is CancellationError {
                runtimeNotice = StorageRuntimeNotice(message: StorageRuntimeCopy.cancelled, isFailure: false)
                return
            } catch {
                runtimeNotice = StorageRuntimeNotice(message: ErrorText.message(for: error), isFailure: true)
                return
            }
            // A Cancel that came after the final rename keeps the runtime but starts nothing.
            if request.startsStorage, !isShuttingDown, !Task.isCancelled { await start()?.value }
        }
        runtimeInstallTask = task
        return task
    }

    /// Stops the running installation before its final rename. Nothing is installed then.
    public func cancelRuntimeInstall() {
        runtimeInstallTask?.cancel()
    }

    public func dismissRuntimeNotice() {
        runtimeNotice = nil
    }

    /// Download, verify, install, and register, then read the new runtime. A failed or cancelled
    /// installation reads the offer again, because a build may now be on this Mac. It throws
    /// `CancellationError` after a cancel.
    private func installRuntime(_ request: StorageRuntimeRequest) async throws {
        runtimeNotice = nil
        runtimeInstallation = StorageRuntimeInstallation(offer: request.offer, startsStorage: request.startsStorage)
        defer { runtimeInstallation = nil }
        do {
            _ = try await port.installRuntime { [weak self] progress in
                Task { @MainActor in self?.show(progress) }
            }
            await refresh()
        } catch {
            await refresh()
            runtimeOffer = await port.runtimeOffer()
            // A cancelled task can end with any error of the step that it stopped.
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    /// Progress that arrives after the installation ended is dropped.
    private func show(_ progress: RuntimeInstallProgress) {
        guard runtimeInstallation != nil else { return }
        runtimeInstallation?.progress = progress
    }
}
