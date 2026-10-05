/// The states of a site change (spec B 3.13). The transaction moves through them in order and
/// records each move, so tests can check every edge.
public enum SiteChangePhase: Equatable, Sendable {
    case idle
    /// S0: an unchanged configuration commits at once.
    case noChange
    /// S1: the plan of sites to run.
    case planning
    /// S2: an interrupted HTTPS setup blocks every change.
    case recoveryGate
    /// S3: preflight, and the approval check.
    case preparing
    /// S3 end: nothing saved; the user must approve.
    case awaitingApproval
    /// S4: a Stop that arrived since the start ends the change before any effect.
    case stopGate
    /// S5: system change, save, and activation.
    case committing
    case committed
    /// S6: restores settings, system setup, and the previous run, once.
    case rollingBack
    /// S7: one report of the failure and of any failed restore step.
    case reporting
}
