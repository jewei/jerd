import Foundation
import JerdFoundation

extension SiteChangeTransaction {
    /// What S5 changed, so S6 undoes exactly that.
    struct Effects: Sendable {
        var changedSystem = false
        var saved = false
    }

    /// S5: system change, save, activation. Any failure rolls back (S6) and reports once (S7).
    func commit(_ context: Context) async throws -> AppConfiguration {
        advance(to: .committing)
        var effects = Effects()
        do {
            try await changeSystem(context, effects: &effects)
            let request = context.request
            if request.candidate != request.previous {
                _ = try await registry.replace(request.candidate, expecting: request.previous)
                effects.saved = true
            }
            guard await !coordinator.isStopRequested(since: context.ticket) else { throw CancellationError() }
            if let plan = context.plan {
                try await coordinator.ensure(plan, prepared: context.prepared, ticket: context.ticket)
            } else if context.running != nil {
                await coordinator.halt()
            }
            advance(to: .committed)
            return request.candidate
        } catch {
            throw await rollBack(context, effects: effects, failure: error)
        }
    }

    /// An approved setup replaces the approved set; otherwise removed hostnames leave it.
    private func changeSystem(_ context: Context, effects: inout Effects) async throws {
        if let approved = context.approved {
            effects.changedSystem = true
            try await gateway.apply(approved)
            return
        }
        let removed = context.request.removedHostnames.intersection(context.status.hostnames)
        guard !removed.isEmpty else { return }
        effects.changedSystem = true
        try await gateway.removeHostnames(removed)
    }
}
