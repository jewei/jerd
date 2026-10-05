import Foundation
import JerdProcess

/// One connector process that Jerd started and owns.
public struct TunnelConnectorHandle: Equatable, Hashable, Sendable {
    public let registrationID: UUID
    /// The supervisor token of the process. Each launch gets a new one.
    public let process: ProcessToken
    public let processID: Int32
    /// The loopback metrics port that this connector must listen on, and nothing else.
    public let metricsPort: UInt16

    package init(registrationID: UUID, process: ProcessToken, processID: Int32, metricsPort: UInt16) {
        self.registrationID = registrationID
        self.process = process
        self.processID = processID
        self.metricsPort = metricsPort
    }
}
