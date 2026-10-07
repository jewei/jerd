import Foundation

/// Plans the one `xcodebuild` call that builds the app. Package versions come only from the committed
/// `Package.resolved`, and all build products stay under `.build`.
enum BuildPlan {
    static func invocation(repository: Repository, toolchain: Toolchain, options: BuildOptions) -> Invocation {
        var arguments = [
            "-project", repository.project.path,
            "-scheme", "Jerd",
            "-configuration", options.configuration.rawValue,
            // This Mac. Debug builds then compile only the architecture of this Mac.
            "-destination", "platform=macOS",
            "-derivedDataPath", repository.derivedData.path,
            "-clonedSourcePackagesDirPath", repository.sourcePackages.path,
            "-onlyUsePackageVersionsFromResolvedFile",
        ]
        if !options.verbose {
            arguments.append("-quiet")
        }
        arguments += signingSettings(options.signing)
        if options.allowsMissingRuntimes {
            arguments.append("JERD_REQUIRE_RUNTIMES=NO")
        }
        arguments.append("build")
        return Invocation(
            executable: toolchain.xcodebuild, arguments: arguments,
            workingDirectory: repository.root, timeout: TimeLimit.build)
    }

    static func signingSettings(_ signing: BuildOptions.Signing?) -> [String] {
        guard let signing else {
            return ["CODE_SIGNING_ALLOWED=NO"]
        }
        return [
            "CODE_SIGN_STYLE=Manual",
            "CODE_SIGN_IDENTITY=\(signing.identity)",
            "DEVELOPMENT_TEAM=\(signing.team)",
        ]
    }

    static func appURL(repository: Repository, configuration: BuildOptions.Configuration) -> URL {
        repository.derivedData.appending(path: "Build/Products/\(configuration.rawValue)/Jerd.app")
    }

    /// The lines that a quiet build shows: compiler and script diagnostics and the final failure line.
    static func isDiagnostic(_ line: String) -> Bool {
        line.contains("error:") || line.contains("warning:") || line.contains("** BUILD FAILED **")
    }
}
