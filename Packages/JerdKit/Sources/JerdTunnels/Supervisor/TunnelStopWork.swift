import Foundation

/// A Stop in progress. Concurrent Stops of one tunnel share it.
struct TunnelStopWork: Sendable {
    let ticket: UUID
    let task: Task<Void, any Error>
}
