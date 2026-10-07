import JerdRuntimes

extension Repository {
    /// `MACOSX_DEPLOYMENT_TARGET` of `Configuration/Base.xcconfig`: the minimum macOS of the app. Every
    /// runtime that `./dev` builds from source targets it, and every embedded payload must run on it.
    func runtimeMinimumMacOS() throws -> MinimumMacOS {
        let file = XcconfigFile(
            path: "Configuration/Base.xcconfig",
            text: try RepositoryPolicy.readText("Configuration/Base.xcconfig", in: self))
        let value = try file.value(of: ReleaseSourceFiles.deploymentTarget)
        guard let minimum = MinimumMacOS(value) else {
            throw DevFailure.checkFailed("Configuration/Base.xcconfig has an invalid MACOSX_DEPLOYMENT_TARGET.")
        }
        return minimum
    }
}
