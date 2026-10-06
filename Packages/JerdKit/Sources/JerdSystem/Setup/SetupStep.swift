/// One effect of a journaled transaction, with its journal phases and its compensation.
struct SetupStep: Sendable {
    /// How a failed `apply` is handled.
    struct Failure: Sendable {
        /// The effect may have happened, so `undo` must run.
        var undo = false
        /// A journal phase that describes the failure.
        var phase: String?
        /// A reason to keep the journal even when every compensation succeeds.
        var retainNote: String?
    }

    /// The name in a rollback summary, for example "host entries".
    let label: String
    /// The phase written before `apply`, when the result of `apply` can be unknown after a crash.
    let startPhase: String?
    /// The phase written after `apply` succeeds.
    let donePhase: String
    let apply: @Sendable () async throws -> Void
    let undo: @Sendable () async throws -> Void
    let classify: @Sendable (any Error) -> Failure

    init(
        label: String, startPhase: String? = nil, donePhase: String, apply: @escaping @Sendable () async throws -> Void,
        undo: @escaping @Sendable () async throws -> Void,
        classify: @escaping @Sendable (any Error) -> Failure = { _ in Failure() }
    ) {
        self.label = label
        self.startPhase = startPhase
        self.donePhase = donePhase
        self.apply = apply
        self.undo = undo
        self.classify = classify
    }
}
