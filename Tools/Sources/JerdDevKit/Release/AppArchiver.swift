import Foundation

/// Archives the Release app and copies it out of the archive. The version comes from
/// `Configuration/Version.xcconfig` of the source commit; there are no version overrides.
struct AppArchiver: Sendable {
    let shell: ReleaseShell
    let inputs: ReleaseInputs
    let layout: CandidateLayout

    func arguments() -> [String] {
        let repository = shell.repository
        return [
            "archive", "-project", repository.project.path, "-scheme", "Jerd", "-configuration", "Release",
            "-destination", "generic/platform=macOS", "-archivePath", layout.archive.path,
            "-derivedDataPath", layout.derivedData.path,
            "-clonedSourcePackagesDirPath", repository.sourcePackages.path,
            "-onlyUsePackageVersionsFromResolvedFile",
            "CODE_SIGN_STYLE=Manual", "CODE_SIGN_IDENTITY=\(inputs.signing.identity)",
            "DEVELOPMENT_TEAM=\(inputs.signing.team)",
        ]
    }

    /// Archives, copies `Jerd.app` to `export/`, and sets the explicit minimum macOS version.
    func run() async throws {
        shell.console.detail("Archive the Release app. This takes several minutes.")
        try await shell.run(
            shell.context.toolchain.xcodebuild, arguments(), limit: TimeLimit.archive, log: layout.log("archive"))
        let products = layout.archive.appending(path: "Products/Applications/Jerd.app")
        try FileManager.default.createDirectory(
            at: layout.app.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await shell.run(SystemProgram.ditto, [products.path, layout.app.path], limit: TimeLimit.appCopy)
        try Self.setMinimumSystem(inputs.minimumMacOS, in: layout.app)
    }

    /// Writes `LSMinimumSystemVersion` into the app's Info.plist before the app is signed again.
    static func setMinimumSystem(_ version: ReleaseVersion, in app: URL) throws {
        let file = app.appending(path: "Contents/Info.plist")
        let data = try Data(contentsOf: file)
        guard var info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw DevFailure.checkFailed("The archived Info.plist is not a dictionary.")
        }
        info["LSMinimumSystemVersion"] = version.text
        let output = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try output.write(to: file, options: .atomic)
    }
}
