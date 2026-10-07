import Foundation

/// The absolute URLs of the external programs. Planning functions read them, so tests use fixed paths.
struct Toolchain: Equatable, Sendable {
    /// Runs `swift` and `swift-format` from the selected Xcode.
    var xcrun: URL
    var xcodebuild: URL
    var git: URL
    /// Reads the architectures of the built executables.
    var lipo: URL
    /// `nil` when XcodeGen is not installed. Only `generate` and `lint` need it.
    var xcodegen: URL?
    /// `nil` when the GitHub CLI is not installed. Only release publishing needs it.
    var gh: URL?

    /// The system shims in `/usr/bin` and the programs found in `PATH`.
    static func live(environment: [String: String]) -> Toolchain {
        let isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
        let path = environment["PATH"]
        return Toolchain(
            xcrun: URL(filePath: "/usr/bin/xcrun"),
            xcodebuild: URL(filePath: "/usr/bin/xcodebuild"),
            git: URL(filePath: "/usr/bin/git"),
            lipo: URL(filePath: "/usr/bin/lipo"),
            xcodegen: ExecutableLocator.find("xcodegen", searchPath: path, isExecutable: isExecutable),
            gh: ExecutableLocator.find("gh", searchPath: path, isExecutable: isExecutable)
        )
    }

    /// Returns XcodeGen or throws the missing-prerequisite failure with the install hint.
    func requireXcodeGen() throws -> URL {
        guard let xcodegen else {
            throw DevFailure.missingPrerequisite(Prerequisite.xcodeGen.missingMessage)
        }
        return xcodegen
    }
}
