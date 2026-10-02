import AppKit
import Observation
import JerdCore

@MainActor @Observable
final class StorageModel {
    var configuration = StorageConfiguration()
    var state = StorageState.stopped
    var processID: Int32?
    var availableBuckets: Set<String> = []
    var selectedName: String? { didSet { if selectedName != oldValue { copiedMessage = nil } } }
    var isLoaded = false
    var isBusy = false
    var isShuttingDown = false
    var errorMessage: String?
    var runtimeMessage = "Preparing RustFS…"
    var copiedMessage: String?
    @ObservationIgnored private var copiedReset: Task<Void, Never>?
    let directory = JSONConfigurationStore.applicationDirectory.appendingPathComponent("storage")
    @ObservationIgnored private lazy var manager = StorageManager(directory: directory)
    private var work: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    var paths: StoragePaths { StoragePaths(root: directory) }
    var canChange: Bool { isLoaded && !isBusy && !isShuttingDown }
    var canAdd: Bool { canChange && configuration.runtime != nil }
    var selected: StorageBucket? { configuration.buckets.first { $0.name == selectedName } }

    func bucketTone(_ bucket: StorageBucket) -> StatusTone {
        if !bucket.setupComplete { return .attention }
        if state != .running { return state.tone }
        return availableBuckets.contains(bucket.name) ? .ready : .attention
    }
    func bucketStatus(_ bucket: StorageBucket) -> String {
        if !bucket.setupComplete { return "Setup incomplete" }
        if state != .running { return "Storage stopped" }
        return availableBuckets.contains(bucket.name) ? "Ready" : "Bucket missing"
    }
    func load() {
        guard !isBusy, !isShuttingDown else { return }
        isBusy = true; errorMessage = nil
        work = Task {
            defer { isBusy = false }
            do {
                configuration = try await manager.load()
                isLoaded = true
                if configuration.runtime == nil, let resources = Bundle.main.resourceURL {
                    do {
                        let runtime = try await BundledStorageRuntime().install(
                            from: resources.appendingPathComponent("StorageRuntime"),
                            into: JSONConfigurationStore.applicationDirectory.appendingPathComponent("storage-runtimes"))
                        if configuration.runtime == nil { try await manager.registerRuntime(runtime) }
                        runtimeMessage = "RustFS is installed."
                    } catch { runtimeMessage = "RustFS setup failed: \(error.localizedDescription)" }
                }
                if let runtime = configuration.runtime { runtimeMessage = "RustFS \(runtime.version) is installed." }
                await refresh()
                if selectedName == nil { selectedName = configuration.buckets.first?.name }
                startMonitoring()
            } catch {
                errorMessage = error.localizedDescription
                runtimeMessage = "Storage settings could not be loaded. The existing file was preserved."
            }
        }
    }
    func start() { perform { try await self.manager.start() } }
    func updateRuntime(_ runtime: StorageRuntime) async throws {
        guard canChange else { throw JerdError.unavailable("Wait for the current storage operation to finish.") }
        isBusy = true; defer { isBusy = false }
        do { try await manager.updateRuntime(runtime); await refresh() }
        catch { await refresh(); throw error }
    }
    func stop() { perform { try await self.manager.stop() } }
    func refreshBuckets() { perform { try await self.manager.refreshBuckets() } }
    func addBucket(name: String, publicRead: Bool, completion: @escaping () -> Void) {
        perform {
            try await self.manager.addBucket(name: name, publicRead: publicRead)
            self.selectedName = name
            completion()
        }
    }
    func retryBucket(_ bucket: StorageBucket) { perform { try await self.manager.retryBucket(bucket.name) } }
    func edit(api: UInt16, console: UInt16, completion: @escaping () -> Void) {
        perform { try await self.manager.edit(apiPort: api, consolePort: console); completion() }
    }
    func suggestPorts() async throws -> (api: UInt16, console: UInt16) { try await manager.suggestedPorts() }
    func showCopied(_ message: String) {
        copiedMessage = message
        copiedReset?.cancel()
        copiedReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.copiedMessage = nil
        }
    }
    func copy(_ part: String, bucket: StorageBucket? = nil) {
        perform {
            let credentials = try await self.manager.credentials()
            let value: String
            if part == "Access key" { value = credentials.accessKey }
            else if part == "Secret key" { value = credentials.secretKey }
            else if let bucket { value = self.configuration.laravelSettings(bucket: bucket, credentials: credentials) }
            else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            self.showCopied("\(part) copied.")
        }
    }
    func openConsole() {
        guard state == .running else { return }
        NSWorkspace.shared.open(configuration.consoleURL)
    }
    func showData() {
        if !NSWorkspace.shared.open(paths.data) { errorMessage = "Start storage once to create its data folder." }
    }
    func openLog() {
        if !NSWorkspace.shared.open(paths.log) { errorMessage = "The storage log is not available yet." }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard canChange else { return }
        isBusy = true; errorMessage = nil; copiedMessage = nil
        work = Task {
            defer { isBusy = false }
            do { try await action() } catch { errorMessage = error.localizedDescription }
            await refresh()
        }
    }
    private func refresh() async {
        let snapshot = await manager.snapshot()
        // Assign only changed values, so idle polling does not refresh the views.
        if configuration != snapshot.configuration { configuration = snapshot.configuration }
        if state != snapshot.state { state = snapshot.state }
        if processID != snapshot.processID { processID = snapshot.processID }
        if availableBuckets != snapshot.availableBuckets { availableBuckets = snapshot.availableBuckets }
    }
    private func startMonitoring() {
        monitor?.cancel()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
            }
        }
    }
    func shutdown() async -> Bool {
        isShuttingDown = true
        await work?.value
        do {
            if isLoaded { try await manager.stop() }
            monitor?.cancel(); await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription; isShuttingDown = false
            await refresh()
            return false
        }
    }
    func resumeAfterCancelledQuit() {
        isShuttingDown = false
        if isLoaded { startMonitoring() }
    }
}
