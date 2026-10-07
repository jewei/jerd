import Foundation
import JerdStorage

extension StorageModel {
    /// Starts storage. Without a runtime it asks to install the pinned RustFS first; the confirmed
    /// installation then starts storage in the same flow.
    @discardableResult
    public func start() -> Task<Void, Never>? {
        guard canStart else { return nil }
        if startInstallsRuntime {
            requestRuntimeInstall(startsStorage: true)
            return nil
        }
        return perform("Starting storage…") { try await $0.port.start() }
    }

    /// Stops storage, or tries again to stop a service that did not stop.
    @discardableResult
    public func stop() -> Task<Void, Never>? {
        guard canStop else { return nil }
        return perform("Stopping storage…") { try await $0.port.stop() }
    }

    @discardableResult
    public func refreshBuckets() -> Task<Void, Never>? {
        guard canChange, state.isRunning else { return nil }
        return perform("Listing buckets…") { try await $0.port.refreshBuckets() }
    }

    /// Continues the setup of an unfinished bucket. It starts storage when needed.
    @discardableResult
    public func retry(_ bucket: StorageBucket) -> Task<Void, Never>? {
        guard canChange, hasRuntime, !bucket.setupComplete else { return nil }
        return perform("Preparing bucket…") { try await $0.port.retryBucket(bucket.name) }
    }

    public func openConsole() {
        guard canOpenConsole else { return }
        workspace.open(settings.consoleURL)
    }

    public func copyEndpoint() {
        copyValue(settings.endpoint, label: "Endpoint")
    }

    /// Copies one connection value, for example the region.
    public func copyValue(_ value: String, label: String) {
        clipboard.copy(value, confirmation: "Copied \(label.lowercased())")
    }

    @discardableResult
    public func copyAccessKey() -> Task<Void, Never> {
        copyCredential(confirmation: "Copied access key") { $0.accessKey }
    }

    @discardableResult
    public func copySecretKey() -> Task<Void, Never> {
        copyCredential(confirmation: "Copied secret key") { $0.secretKey }
    }

    /// Copies the Laravel settings of a bucket whose setup is complete.
    @discardableResult
    public func copyEnvironment(for bucket: StorageBucket) -> Task<Void, Never> {
        let settings = settings
        return copyCredential(confirmation: "Copied Laravel settings") { credentials in
            settings.laravelEnvironment(bucket: bucket, credentials: credentials)
        }
    }

    public func revealData() {
        guard let files, files.hasDataFolder else { return }
        workspace.reveal(files.dataFolder)
    }

    public func openLog() {
        guard let files, files.hasLog else { return }
        workspace.open(files.log)
    }

    public func showRuntimes() {
        navigate?(.dashboard(.runtimes))
    }

    /// Reads the credentials and copies one value. It runs beside other work and never
    /// changes the operation unless the read fails.
    private func copyCredential(
        confirmation: String, _ value: @escaping @Sendable (StorageCredentials) -> String
    ) -> Task<Void, Never> {
        Task {
            do {
                let credentials = try await port.credentials()
                clipboard.copy(value(credentials), confirmation: confirmation)
            } catch {
                if !operation.isWorking { operation = .failed(message: ErrorText.message(for: error)) }
            }
        }
    }
}
