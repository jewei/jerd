import Foundation
import JerdServiceKit

/// The registry and the state of every registered service, for the Databases page.
public struct DatabaseSnapshot: Equatable, Sendable {
    public let configuration: DatabaseConfiguration
    /// One state for each registered service.
    public let states: [UUID: ServiceState]

    public init(configuration: DatabaseConfiguration, states: [UUID: ServiceState]) {
        self.configuration = configuration
        self.states = states
    }

    /// The state of `id`; `stopped` for a service without an instance yet.
    public func state(of id: UUID) -> ServiceState { states[id] ?? .stopped }
}
