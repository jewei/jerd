/// The operations that the stop engine needs from one owned process group.
protocol StopTarget: Sendable {
    /// The leader state, read without reaping.
    func leaderState() -> ProcessState
    /// Sends a signal to the leader only.
    func signalLeader(_ signal: Int32)
    /// Sends a signal to the whole process group.
    func signalGroup(_ signal: Int32)
    /// Waits until the leader exits or the deadline passes. Returns true when the leader exited.
    func waitForLeaderExit(until deadline: ContinuousClock.Instant) async -> Bool
    /// Waits until the leader exited and no other live member remains. Unknown counts as "remains".
    func waitForEmptyGroup(until deadline: ContinuousClock.Instant) async -> Bool
    /// True unless the group is proven to have no live member other than the leader.
    func mayHaveOtherMembers() -> Bool
}
