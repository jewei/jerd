import Foundation

/// Plans what `./dev clean` removes. It removes only build output folders inside the repository.
enum CleanPlan {
    static func targets(repository: Repository, all: Bool) -> [URL] {
        var targets = [
            repository.derivedData,
            repository.snapshots,
            repository.path("Packages/JerdKit/.build"),
            repository.path("Tools/.build"),
        ]
        if all {
            targets += [repository.sourcePackages, repository.runtimes]
        }
        return targets
    }

    /// A last guard before removal: the folder is inside the repository and inside a `.build` folder.
    static func isSafeToRemove(_ url: URL, repository: Repository) -> Bool {
        let relative = repository.relativePath(of: url)
        let components = relative.split(separator: "/")
        return !relative.hasPrefix("/") && components.contains(".build") && !components.contains("..")
    }
}
