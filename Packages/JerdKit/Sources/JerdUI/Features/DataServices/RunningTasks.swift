import Foundation

/// The tasks of one service feature that Quit waits for. A task leaves the list only when it
/// ends, so Quit also waits for a save whose sheet the user cancelled.
@MainActor
final class RunningTasks {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    nonisolated init() {}

    /// True while no task of the feature runs.
    var isEmpty: Bool { tasks.isEmpty }

    /// Runs `work` and keeps its task until it ends. In `work`, `Task.isCancelled` tells that
    /// the user cancelled the wait.
    func run(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { @MainActor [weak self] in
            await work()
            self?.tasks[id] = nil
        }
        tasks[id] = task
        return task
    }

    /// Waits until every task has ended, also a task that starts during the wait.
    func waitForAll() async {
        while let task = tasks.values.first {
            await task.value
        }
    }
}
