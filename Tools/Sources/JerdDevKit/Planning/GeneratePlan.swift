import Foundation

/// Plans XcodeGen runs. `--check` generates into a temporary copy of the repository, because XcodeGen
/// writes paths relative to the project folder and a project in another folder never matches.
enum GeneratePlan {
    /// Generates `Jerd.xcodeproj` from `project.yml` in `root`.
    static func generate(root: URL, xcodegen: URL) -> Invocation {
        Invocation(
            executable: xcodegen,
            arguments: ["generate", "--quiet", "--spec", root.appending(path: "project.yml").path],
            workingDirectory: root,
            timeout: TimeLimit.generate)
    }

    /// Lists the files that XcodeGen can read: tracked files and new files that Git does not ignore.
    static func listSourceFiles(repository: Repository, toolchain: Toolchain) -> Invocation {
        Invocation(
            executable: toolchain.git,
            arguments: ["-C", repository.root.path, "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
            timeout: TimeLimit.git)
    }

    /// The files to copy for a check: every listed file except the committed project, which the
    /// generator must make again.
    static func filesToCopy(fromGitOutput output: String, projectFolder: String = "Jerd.xcodeproj") -> [String] {
        output.split(separator: "\0", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.hasPrefix(projectFolder + "/") }
    }
}
