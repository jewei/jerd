/// Proof of when an operation began, compared with later Stop requests.
///
/// A Stop raises the coordinator's stop epoch. Every step of an operation that began before the
/// Stop sees a stale ticket and ends with `CancellationError`, so a Stop is never lost, also when
/// it arrives between two steps (spec B 7.1.3). An operation that begins after the Stop gets a new
/// ticket and runs.
public struct StopTicket: Equatable, Hashable, Sendable {
    let epoch: UInt64
}
