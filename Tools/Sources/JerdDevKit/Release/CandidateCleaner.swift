import Foundation

/// `./dev release clean`: removes old candidates (each takes about 2.5 GB) and keeps the newest ones
/// and every candidate that a publication still needs.
struct CandidateCleaner: Sendable {
    let environment: ReleaseEnvironment

    /// - Returns: the names of the removed candidates.
    @discardableResult
    func run(keep: Int) throws -> [String] {
        let store = CandidateStore(releases: environment.repository.releases)
        let candidates = try store.candidates()
        let selection = CandidateSelection.select(candidates.map(\.candidate), keep: keep)
        let console = environment.console
        for (name, reason) in selection.protected {
            console.warning("Kept \(name): \(reason).")
        }
        for name in selection.remove {
            guard let layout = candidates.first(where: { $0.candidate.name == name })?.layout,
                CleanPlan.isSafeToRemove(layout.root, repository: environment.repository)
            else { continue }
            try FileManager.default.removeItem(at: layout.root)
            console.detail("Removed \(name).")
        }
        console.success("Removed \(selection.remove.count) of \(candidates.count) candidates.")
        return selection.remove
    }
}
