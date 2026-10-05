import Foundation

/// Removes build output. It prints each folder before it removes it, and it refuses any folder that is
/// not a `.build` folder inside the repository.
enum CleanStep {
    static func run(_ context: DevContext, all: Bool) throws {
        let manager = FileManager.default
        let repository = context.repository
        let existing = CleanPlan.targets(repository: repository, all: all)
            .filter { manager.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else {
            context.console.success("Nothing to remove.")
            return
        }
        if let unsafe = existing.first(where: { !CleanPlan.isSafeToRemove($0, repository: repository) }) {
            throw DevFailure.checkFailed("Refused to remove \(unsafe.path): it is not a build folder.")
        }
        context.console.detail("These folders will be removed:")
        existing.forEach { context.console.detail("  \(repository.relativePath(of: $0))") }
        for folder in existing {
            try manager.removeItem(at: folder)
        }
        context.console.success("Removed \(existing.count) folders.")
    }
}
