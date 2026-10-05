import Foundation

/// Checks the app that a build made with `BuiltAppPolicy`. `./dev build` and so `./dev check` run it
/// after every successful build.
enum BuiltAppStep {
    static func check(_ context: DevContext, app: URL) async throws {
        let repository = context.repository
        let plist = app.appending(path: BuiltAppPolicy.infoPlist)
        var findings: [PolicyFinding]
        if let data = try? Data(contentsOf: plist) {
            findings = BuiltAppPolicy.infoPlistFindings(data, file: repository.relativePath(of: plist))
        } else {
            findings = [PolicyFinding(file: repository.relativePath(of: plist), message: "The file is missing.")]
        }
        for executable in BuiltAppPolicy.executables {
            let file = app.appending(path: executable)
            let probe = Invocation(
                executable: context.toolchain.lipo, arguments: ["-archs", file.path], timeout: TimeLimit.probe)
            let result = try await context.run(probe, output: .capture)
            findings += BuiltAppPolicy.architectureFindings(
                file: repository.relativePath(of: file), lipoOutput: result.succeeded ? result.standardOutput : nil)
        }
        guard findings.isEmpty else {
            findings.forEach { context.console.error($0.description) }
            throw DevFailure.checkFailed("The built app does not have the required settings.")
        }
        context.console.success("The built Info.plist has the pinned update feed URL, public key, and Sparkle keys.")
        context.console.success("Jerd, JerdCLI, and JerdHelper contain only arm64.")
    }
}
