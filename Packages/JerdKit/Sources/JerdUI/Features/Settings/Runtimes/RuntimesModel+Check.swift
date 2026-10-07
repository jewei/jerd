import JerdManifest
import JerdRuntimes

extension RuntimesModel {
    /// Checks every runtime kind, at most three sources at a time. Each result shows as soon as
    /// it arrives. A check never runs at launch; only the user starts it.
    @discardableResult
    public func check() -> Task<Void, Never>? {
        guard canCheck else { return nil }
        isChecking = true
        let task = Task { [port] in
            await withTaskGroup(of: RuntimeUpdateCheck.self) { group in
                var pending = RuntimeKind.allCases.makeIterator()
                for _ in 0..<Self.checkConcurrency {
                    guard let kind = pending.next() else { break }
                    group.addTask { await port.check(kind) }
                }
                for await result in group {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        break
                    }
                    apply(result)
                    if let kind = pending.next() {
                        group.addTask { await port.check(kind) }
                    }
                }
            }
            isChecking = false
        }
        checkTask = task
        return task
    }

    /// Shows one check result and keeps or chooses the selected release.
    func apply(_ check: RuntimeUpdateCheck) {
        checks[check.kind] = check
        selections[check.kind] = RuntimeSelectionPolicy.selection(
            after: check, current: selections[check.kind], defaultPHPVersion: registry.defaultPHP?.version)
    }
}
