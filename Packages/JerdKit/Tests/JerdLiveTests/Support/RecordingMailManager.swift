import JerdFoundation
import JerdMail
import JerdServiceKit

@testable import JerdLive

/// A mail manager in memory. It records the calls that the port forwards.
actor RecordingMailManager: MailManaging {
    private(set) var settings: MailSettings
    private(set) var calls: [String] = []
    let loadFailure: JerdError?

    init(_ settings: MailSettings = MailSettings(), loadFailure: JerdError? = nil) {
        self.settings = settings
        self.loadFailure = loadFailure
    }

    func load() throws -> MailSettings {
        calls.append("load")
        if let loadFailure { throw loadFailure }
        return settings
    }

    func snapshot() -> MailSnapshot { MailSnapshot(settings: settings, state: .stopped) }

    func registerRuntime(_ runtime: MailRuntime) {
        calls.append("register \(runtime.id)")
        settings.runtime = runtime
    }

    /// Like the live manager: an update needs a saved runtime.
    func updateRuntime(_ runtime: MailRuntime) throws {
        calls.append("update \(runtime.id)")
        guard settings.runtime != nil else { throw JerdError.unavailable("The Mailpit runtime is not installed.") }
        settings.runtime = runtime
    }

    func suggestedPorts() -> MailPorts { MailSettings.defaultPorts }
    func edit(ports: MailPorts) { calls.append("edit") }
    func start() { calls.append("start") }
    func stop() { calls.append("stop") }
    func sendTestEmail() { calls.append("sendTestEmail") }
}
