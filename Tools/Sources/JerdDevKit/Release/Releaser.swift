import Foundation

/// `./dev release VERSION BUILD`: the whole release in one run. All local work comes first (checks,
/// build, signatures, notarization, the signed candidate feed). Then the public steps run in a fixed
/// order. The run stops at the first failed step and prints what is public and how to recover.
/// With `--prepare-only` it stops after the local work.
struct Releaser: Sendable {
    let environment: ReleaseEnvironment
    let request: ReleaseRequest
    /// The local steps. Tests replace them, so nothing is built or sent to Apple.
    var localSteps: @Sendable (ReleaseBuilder) -> [ReleaseStep] = { $0.steps }

    var console: Console { environment.console }

    func run() async throws {
        var sequence = StepSequence(console: console)
        var checked: (inputs: ReleaseInputs, source: ReleaseSource)?
        await sequence.run("Check preconditions") { checked = try await checkPreconditions() }
        guard let (inputs, source) = checked, sequence.exitStatus == .success else {
            return try finish(sequence, phase: .local, facts: nil)
        }
        let layout = CandidateLayout(
            releases: environment.repository.releases, version: inputs.version, build: inputs.build)
        let facts = ReleasePublication.facts(
            inputs: inputs, commit: source.commit, layout: layout, repository: environment.repository)
        var steps = localSteps(ReleaseBuilder(environment: environment, inputs: inputs, source: source, layout: layout))
        if !inputs.prepareOnly {
            steps += ReleasePublication(environment: environment, inputs: inputs, source: source, layout: layout).steps
        }
        var phase = ReleasePhase.local
        Self.noteForInterrupt(phase, facts: facts)
        for step in steps {
            if let start = step.startPhase { phase = start }
            Self.noteForInterrupt(phase, facts: facts)
            await sequence.run(step.title) { try await step.run() }
            guard sequence.exitStatus == .success else { break }
            if let end = step.endPhase { phase = end }
        }
        if sequence.exitStatus == .success, inputs.prepareOnly {
            console.success(
                "Candidate ready in \(environment.repository.relativePath(of: layout.root)). "
                    + "Nothing was published, and no tracked file changed.")
        }
        try finish(sequence, phase: phase, facts: facts)
    }

    /// The inputs with the selected identity, the checked source, and the ready credentials and payloads.
    func checkPreconditions() async throws -> (inputs: ReleaseInputs, source: ReleaseSource) {
        let shell = environment.shell
        let files = ReleaseSourceFiles(repository: environment.repository, verifier: environment.verifier)
        let inputs = try ReleaseInputs.parse(
            request, deploymentTarget: try files.deploymentTarget(),
            identities: try await ReleasePreflight.identities(shell))
        let source = try await ReleasePreconditions(environment: environment, inputs: inputs).check()
        try await ReleasePreflight(shell: shell, inputs: inputs).run()
        let mode = inputs.prepareOnly ? " as a private candidate (--prepare-only)" : ""
        console.detail(
            "Release Jerd \(inputs.version) (build \(inputs.build)) for macOS \(inputs.minimumMacOS) from "
                + "\(source.commit.prefix(12))\(mode).")
        return (inputs, source)
    }

    /// Prints the summary, and after a failure what is public and the recovery commands.
    func finish(_ sequence: StepSequence, phase: ReleasePhase, facts: ReleasePhase.Facts?) throws {
        SignalForwarder.setInterruptNote(nil)
        do {
            try sequence.finish()
        } catch {
            let lines = facts.map(phase.recovery) ?? ReleasePhase.local.recovery(Self.noFacts)
            if let first = lines.first { console.warning(first) }
            lines.dropFirst().forEach(console.detail)
            throw error
        }
    }

    /// A stop by signal ends `./dev` at once, so the recovery text of the phase is set in advance.
    static func noteForInterrupt(_ phase: ReleasePhase, facts: ReleasePhase.Facts) {
        SignalForwarder.setInterruptNote(phase.recovery(facts).joined(separator: "\n"))
    }

    private static let noFacts = ReleasePhase.Facts(
        tag: "", title: "", sourceCommit: "", diskImage: "", symbols: "", notes: "")
}
