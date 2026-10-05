import Foundation
import JerdProcess

extension CloudflaredConnector {
    /// Ready only when the owned connector listens on exactly `127.0.0.1:<metricsPort>`, no other
    /// process shares that port, and `/ready` answers 200 while the connector still runs.
    public func readiness(of handle: TunnelConnectorHandle) async throws -> TunnelReadiness {
        guard await isRunning(handle) else { return .waiting }
        let directory = layout.instance(handle.registrationID).root
        let listeners = try await commands.run(
            MetricsEndpoint.listenersRequest(processID: handle.processID, directory: directory),
            timeout: MetricsEndpoint.inspectionTimeout)
        switch MetricsEndpoint.listenerVerdict(listeners, port: handle.metricsPort) {
        case .none: return .waiting
        case .unexpected: return .unexpectedListener
        case .expected: break
        }
        let owners = try await commands.run(
            MetricsEndpoint.ownersRequest(port: handle.metricsPort, directory: directory),
            timeout: MetricsEndpoint.inspectionTimeout)
        guard MetricsEndpoint.ownersMatch(owners, processID: handle.processID) else { return .unexpectedListener }
        let response = try await commands.run(
            MetricsEndpoint.readyRequest(port: handle.metricsPort, directory: directory),
            timeout: MetricsEndpoint.readyTimeout)
        // A connector that exited during the request cannot be ready, whatever answered.
        guard await isRunning(handle) else { return .waiting }
        return MetricsEndpoint.isReady(response) ? .ready : .waiting
    }
}
