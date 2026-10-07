/// One named step of `./dev release`. A public step moves the release to `startPhase` before it runs
/// and to `endPhase` after it succeeds, so a failure names what is already public.
struct ReleaseStep: Sendable {
    var title: String
    var startPhase: ReleasePhase?
    var endPhase: ReleasePhase?
    var run: @Sendable () async throws -> Void

    init(
        _ title: String, startPhase: ReleasePhase? = nil, endPhase: ReleasePhase? = nil,
        run: @escaping @Sendable () async throws -> Void
    ) {
        self.title = title
        self.startPhase = startPhase
        self.endPhase = endPhase
        self.run = run
    }
}
