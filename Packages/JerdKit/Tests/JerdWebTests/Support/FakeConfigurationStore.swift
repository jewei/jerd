import Foundation
import JerdFoundation

@testable import JerdWeb

/// An in-memory configuration store that can fail or pause the next save.
actor FakeConfigurationStore: ConfigurationStoring {
    private(set) var saved: AppConfiguration
    private(set) var saves = 0
    private var failNext = false
    private var pauseNext = false
    private var waiter: CheckedContinuation<Void, Never>?
    private(set) var isPaused = false

    init(_ configuration: AppConfiguration = AppConfiguration()) {
        saved = configuration
    }

    func load() -> AppConfiguration { saved }

    func save(_ configuration: AppConfiguration) async throws {
        saves += 1
        if pauseNext {
            pauseNext = false
            isPaused = true
            await withCheckedContinuation { waiter = $0 }
            isPaused = false
        }
        if failNext {
            failNext = false
            throw JerdError.unavailable("Test save failure")
        }
        saved = configuration
    }

    func failNextSave() { failNext = true }
    func pauseNextSave() { pauseNext = true }

    func resume() {
        waiter?.resume()
        waiter = nil
    }
}

/// A hosts reader with a fixed text, or a fixed error.
struct FakeHostsFile: HostsFileReading {
    var text = ""
    var error: JerdError?

    func read() throws -> String {
        if let error { throw error }
        return text
    }
}

/// Waits until `condition` holds, yielding between checks. Fails the test after the timeout.
func waitUntil(timeout: Duration = .seconds(5), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
}
