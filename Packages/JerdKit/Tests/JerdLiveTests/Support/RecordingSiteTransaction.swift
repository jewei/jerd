import Foundation
import JerdFoundation
import JerdWeb

@testable import JerdLive

/// A site change transaction that records each change and answers with set steps. A committed
/// change also updates the shared registry fake, as the real transaction saves it.
actor RecordingSiteTransaction: SiteChangeApplying {
    private(set) var changes: [SiteChange] = []
    private(set) var runs: [Set<UUID>] = []
    private var steps: [SiteChangeStep] = []
    let registry: FakeSiteRegistry?
    let journal: CallJournal?

    init(registry: FakeSiteRegistry? = nil, journal: CallJournal? = nil) {
        self.registry = registry
        self.journal = journal
    }

    /// The next answers, in order. Without a queued step a change commits.
    func enqueue(_ step: SiteChangeStep) {
        steps.append(step)
    }

    func apply(_ change: SiteChange, startIfStopped: Bool) async throws -> SiteChangeStep {
        changes.append(change)
        await journal?.record("transaction.apply")
        return try await next(applying: change)
    }

    func run(_ siteIDs: Set<UUID>) async throws -> SiteChangeStep {
        runs.append(siteIDs)
        await journal?.record("transaction.run")
        return try await next(applying: nil)
    }

    func requestStop() async {
        await journal?.record("transaction.requestStop")
    }

    private func next(applying change: SiteChange?) async throws -> SiteChangeStep {
        if !steps.isEmpty { return steps.removeFirst() }
        guard let registry else { return .committed(AppConfiguration()) }
        if let change { await registry.reduce(change) }
        return .committed(try await registry.snapshot())
    }
}
