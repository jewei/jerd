import JerdFoundation
import JerdServiceKit
import JerdStorage

@testable import JerdLive

/// A storage manager in memory. It records the calls that the port forwards.
actor RecordingStorageManager: StorageManaging {
    private(set) var settings: StorageSettings
    private(set) var calls: [String] = []
    let loadFailure: JerdError?

    init(_ settings: StorageSettings = StorageSettings(), loadFailure: JerdError? = nil) {
        self.settings = settings
        self.loadFailure = loadFailure
    }

    func load() throws -> StorageSettings {
        calls.append("load")
        if let loadFailure { throw loadFailure }
        return settings
    }

    func snapshot() -> StorageSnapshot { StorageSnapshot(settings: settings, state: .stopped, availableBuckets: []) }

    func registerRuntime(_ runtime: StorageRuntime) {
        calls.append("register \(runtime.id)")
        settings.runtime = runtime
    }

    func start() { calls.append("start") }
    func stop() { calls.append("stop") }
    func addBucket(name: String, publicRead: Bool) { calls.append("addBucket \(name) \(publicRead)") }
    func retryBucket(_ name: String) { calls.append("retryBucket \(name)") }
    func refreshBuckets() { calls.append("refreshBuckets") }
    func credentials() throws -> StorageCredentials { throw JerdError.unavailable("Not used by this test.") }
    func suggestedPorts() -> StoragePorts { StorageSettings.defaultPorts }
    func edit(ports: StoragePorts) { calls.append("edit") }
}
