import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit
import JerdServiceKitTestSupport
import os

/// The runtime record of the fake single-instance service. An empty name is invalid.
struct FakeRuntime: SingleServiceRuntime, Codable {
    var name: String
    var isValid: Bool { !name.isEmpty }
}

/// One port. Ports below 1024 are invalid.
struct FakePorts: SingleServicePorts, Codable {
    var port: UInt16
    var ordered: [UInt16] { [port] }
}

struct FakeSingleSettings: SingleServiceSettings, Codable {
    var runtime: FakeRuntime?
    var ports = FakePorts(port: 41_001)

    func validate() throws {
        guard ports.port >= 1_024 else { throw JerdError.invalid("The fake ports are invalid.") }
    }
}

/// A single-instance service on top of `InstanceHarness`, with `settings.json` in the instance
/// folder (so an update backs it up and restores it), a scripted save failure, and recorded
/// update steps.
final class FakeSingleService: SingleServiceDescribing {
    static let messages = SingleServiceMessages(
        busy: "The fake service is busy.", notLoaded: .unavailable("Load the fake service."),
        updatePending: .unavailable("Recover the fake update."), runtimeMissing: .unavailable("No fake runtime."),
        runtimeChanged: .invalid("The fake runtime changed."), runtimeRecordInvalid: .invalid("Bad fake runtime."),
        recoveryWithoutRuntime: .corrupt("No fake runtime to recover."),
        stopBeforeEditing: .unavailable("Stop the fake service first."))

    let harness: InstanceHarness
    private let saveError = OSAllocatedUnfairLock<JerdError?>(initialState: nil)

    init(harness: InstanceHarness) { self.harness = harness }

    var root: URL { harness.folder }
    var messages: SingleServiceMessages { Self.messages }
    var updateTransaction: RuntimeUpdateTransaction {
        RuntimeUpdateBackupTests.transaction(harness, names: ["settings.json"])
    }

    var settingsFile: URL { harness.folder.appendingPathComponent("settings.json") }

    /// The settings on disk, or nil without a file.
    var saved: FakeSingleSettings? {
        try? JSONDecoder().decode(FakeSingleSettings.self, from: AtomicFile.read(settingsFile, limit: 4_096))
    }

    /// Makes every later save fail with `error`, or succeed with nil.
    func setSaveError(_ error: JerdError?) { saveError.withLock { $0 = error } }

    func loadSettings() throws -> FakeSingleSettings {
        guard exists(settingsFile) else { return FakeSingleSettings() }
        return try JSONDecoder().decode(FakeSingleSettings.self, from: AtomicFile.read(settingsFile, limit: 4_096))
    }

    func save(_ settings: FakeSingleSettings, replacing previous: FakeRuntime?) throws {
        if let error = saveError.withLock({ $0 }) { throw error }
        if let old = saved?.runtime, old != settings.runtime, old != previous {
            throw JerdError.invalid("The saved fake runtime cannot change.")
        }
        try AtomicFile.write(try JSONEncoder().encode(settings), to: settingsFile)
    }

    func definition(runtime: FakeRuntime, ports: FakePorts) -> any ServiceDefinition {
        harness.definition(name: runtime.name)
    }

    func suggestPorts(using ports: LoopbackPortGuard) async throws -> FakePorts {
        FakePorts(port: try await ports.suggest(startingAt: 41_001))
    }

    func validateData(for runtime: FakeRuntime) throws { harness.events.add("validate \(runtime.name)") }

    func adoptData(_ runtime: FakeRuntime) throws { harness.events.add("adopt \(runtime.name)") }
}
