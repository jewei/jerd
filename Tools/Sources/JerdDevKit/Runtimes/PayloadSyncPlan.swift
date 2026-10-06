import Foundation

/// Plans how the embed phase makes `Jerd.app/Contents/Resources/RuntimePayloads` equal to the verified
/// payloads: one `rsync --delete` per payload folder, so unchanged files are not copied again on
/// every build, and the removal of every folder that no current pin names.
enum PayloadSyncPlan {
    /// Copies changed files of `source` into `destination` and removes files that `source` lacks.
    /// Finder metadata is never copied; installation ignores it too.
    static func copy(_ source: URL, to destination: URL) -> Invocation {
        Invocation(
            executable: SystemProgram.rsync,
            arguments: [
                "-a", "--delete", "--exclude=.DS_Store", source.path + "/", destination.path + "/",
            ],
            timeout: TimeLimit.payloadCopy)
    }

    /// The paths below the destination that do not belong to the expected layout, sorted. `existing`
    /// maps each top-level name to its entries (empty for a file); `expected` maps each group folder to
    /// its payload IDs. The catalog file is always expected.
    static func extraneous(
        existing: [String: [String]], expected: [String: Set<String>], catalogName: String
    ) -> [String] {
        var paths: [String] = []
        for (name, children) in existing where name != catalogName {
            guard let ids = expected[name] else {
                paths.append(name)
                continue
            }
            paths += children.filter { !ids.contains($0) }.map { "\(name)/\($0)" }
        }
        return paths.sorted()
    }
}
