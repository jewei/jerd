/// The run state machine of the web environment. The gateway and the site change transaction
/// depend on this role so tests can use a fake.
///
/// It has no rollback policy: it never restarts a previous plan on its own. The site change
/// transaction owns rollback.
public protocol EnvironmentCoordinating: Sendable {
    func snapshot() async -> EnvironmentSnapshot
    /// The plan that runs now, or nil.
    func runningPlan() async -> ServingPlan?
    /// A ticket for an operation that begins now.
    func ticket() async -> StopTicket
    /// True when a Stop arrived after `ticket` was issued.
    func isStopRequested(since ticket: StopTicket) async -> Bool
    /// Validates `plan` in a throwaway tree and returns a one-use token.
    func preflight(_ plan: ServingPlan, ticket: StopTicket) async throws -> PreparedPlan
    /// Keeps a healthy equivalent run, or replaces the run with `plan`. An empty plan stops the run.
    func ensure(_ plan: ServingPlan, prepared: PreparedPlan?, ticket: StopTicket) async throws
    /// Stops the run for a system change. It is not a Stop request, so it cancels nothing.
    func halt() async
    /// Records that HTTPS setup was removed.
    func markSetupRemoved() async
    /// The user's Stop: every operation that began before it ends, and nothing new starts from it.
    func requestStop() async
    /// `requestStop()`, then waits for the current operation and stops the run.
    func stop() async
}
