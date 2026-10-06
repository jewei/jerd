import Foundation
import JerdProcess

/// What one single-instance service (Mail, Storage) adds to `SingleServiceCoordinator`: its
/// folder, settings file, definition, suggested ports, data checks, and messages.
package protocol SingleServiceDescribing: Sendable {
    associatedtype Settings: SingleServiceSettings

    /// The service folder. `load()` creates it with mode 0700.
    var root: URL { get }
    var messages: SingleServiceMessages { get }
    /// The runtime update of the service folder, with the items that it backs up.
    var updateTransaction: RuntimeUpdateTransaction { get }

    /// The saved settings, or the defaults when the file is absent. Nothing is written.
    func loadSettings() throws -> Settings
    /// Saves `settings`. The saved runtime may change only to replace `previous`.
    func save(_ settings: Settings, replacing previous: Settings.Runtime?) throws
    /// The service definition of `runtime` on `ports`.
    func definition(runtime: Settings.Runtime, ports: Settings.Ports) -> any ServiceDefinition
    /// Free default ports for a new registration.
    func suggestPorts(using ports: LoopbackPortGuard) async throws -> Settings.Ports
    /// Checks the saved data against `runtime` without a write, before an update backs it up.
    func validateData(for runtime: Settings.Runtime) throws
    /// Moves the saved data markers to `runtime` during an update.
    func adoptData(_ runtime: Settings.Runtime) throws
    /// Extra checks of the updated, ready service, for example that every bucket is listed.
    func verifyUpdatedService(_ settings: Settings) async throws
}

extension SingleServiceDescribing {
    /// Most services have no extra check after an update.
    package func verifyUpdatedService(_ settings: Settings) async throws {}
}
