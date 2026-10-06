import Foundation
import JerdFoundation
import JerdServiceKit

/// The shared stop answer of the in-memory services.
enum ServiceStop {
    /// The state after a stop with `behavior`, or the error that the stop throws.
    static func apply(_ behavior: ServiceBehavior, to state: ServiceState) async throws -> ServiceState {
        switch behavior {
        case .succeed:
            return .stopped
        case .fail(let reason):
            throw JerdError.processFailed(reason)
        case .stuck(let reason):
            throw StuckError(state: .stuck(pid: state.processID ?? 4999, reason: reason), reason: reason)
        case .suspend:
            try await ServiceBehavior.waitForCancellation()
        }
    }
}
