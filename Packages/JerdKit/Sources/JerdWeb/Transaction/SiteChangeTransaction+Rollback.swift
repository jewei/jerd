import Foundation
import JerdFoundation

extension SiteChangeTransaction {
    /// S6 and S7: undoes the effects once, in a task that a Stop or a cancellation cannot cut
    /// short, and returns the one error to report.
    func rollBack(_ context: Context, effects: Effects, failure: any Error) async -> any Error {
        advance(to: .rollingBack)
        let registry = registry
        let gateway = gateway
        let coordinator = coordinator
        let problems = await Task.detached {
            var problems: [String] = []
            if effects.saved {
                do {
                    _ = try await registry.replace(context.request.previous, expecting: context.request.candidate)
                } catch {
                    problems.append("Settings: \(FailureDetail.describe(error))")
                }
            }
            if effects.changedSystem, let problem = await Self.restoreSystem(context.status, gateway) {
                problems.append(problem)
            }
            if let problem = await Self.restoreRun(context, coordinator) { problems.append(problem) }
            return problems
        }.value
        advance(to: .reporting)
        return Self.report(failure, problems: problems)
    }

    private static func restoreSystem(_ saved: HTTPSSetupStatus, _ gateway: any SystemSetupManaging) async -> String? {
        do {
            let current = try await gateway.status()
            guard !current.hasPendingRecovery else { return "HTTPS: HTTPS setup needs approved recovery in Advanced." }
            if current != saved { try await gateway.restore(saved) }
            return nil
        } catch {
            return "HTTPS: \(FailureDetail.describe(error))"
        }
    }

    /// Restarts the previous run once, unless the user stopped it. A Stop during the restart
    /// ends it without a problem.
    private static func restoreRun(_ context: Context, _ coordinator: any EnvironmentCoordinating) async -> String? {
        guard let running = context.running, await !coordinator.isStopRequested(since: context.ticket) else {
            return nil
        }
        do {
            try await coordinator.ensure(running, prepared: nil, ticket: context.ticket)
            return nil
        } catch is CancellationError {
            return await coordinator.isStopRequested(since: context.ticket)
                ? nil : "Restart: The restart was cancelled."
        } catch {
            return "Restart: \(FailureDetail.describe(error))"
        }
    }

    /// One message: restore problems first, then a Stop as itself, then the restored failure.
    private static func report(_ failure: any Error, problems: [String]) -> any Error {
        let detail = failure is CancellationError ? "The change was stopped." : FailureDetail.describe(failure)
        if !problems.isEmpty {
            return JerdError.processFailed(
                "The site change failed: \(detail) Recovery needs attention. \(problems.joined(separator: " "))")
        }
        if failure is CancellationError { return failure }
        return JerdError.processFailed("The site change failed. The previous settings were restored. \(detail)")
    }
}
