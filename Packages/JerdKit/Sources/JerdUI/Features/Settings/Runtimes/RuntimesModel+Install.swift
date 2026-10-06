import JerdManifest
import JerdRuntimes

extension RuntimesModel {
    /// Installs a release and puts it into use. Only one installation runs at a time.
    /// - Parameter useAsDefault: For PHP: also make it the default. "Install Only" passes false.
    @discardableResult
    public func install(_ release: RuntimeRelease, useAsDefault: Bool = true) -> Task<Void, Never>? {
        guard canChangeRuntimes else { return nil }
        let kind = release.kind
        installation = RuntimeInstallation(kind: kind)
        errors[kind] = nil
        messages[kind] = nil
        let task = Task {
            await runInstallation(release, useAsDefault: useAsDefault)
            installation = nil
            await load()
        }
        installTask = task
        return task
    }

    /// Cancels the installation, unless activation already started.
    public func cancelInstall() {
        guard installation?.canCancel == true else { return }
        installTask?.cancel()
    }

    private func runInstallation(_ release: RuntimeRelease, useAsDefault: Bool) async {
        let kind = release.kind
        do {
            let build = try await port.install(release) { [weak self] progress in
                Task { @MainActor in self?.show(progress, for: kind) }
            }
            try Task.checkCancellation()
            installation?.isActivating = true
            try await port.activate(build, useAsDefault: useAsDefault)
            messages[kind] = RuntimeCopy.installedMessage(kind, version: build.version, useAsDefault: useAsDefault)
        } catch is CancellationError {
            messages[kind] = RuntimeCopy.cancelledMessage
        } catch {
            errors[kind] = ErrorText.message(for: error)
        }
    }

    /// Progress that arrives after the installation ended is dropped.
    private func show(_ progress: RuntimeInstallProgress, for kind: RuntimeKind) {
        guard installation?.kind == kind else { return }
        installation?.progress = progress
    }
}
