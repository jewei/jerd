import Foundation

/// Signs Sparkle's nested code, the launcher, the helper, and the app with Developer ID.
///
/// Archive signing leaves Sparkle's tools with their upstream signatures, so they are signed again in
/// Sparkle's documented order, innermost first. Every signature names its identifier: Sparkle keeps
/// the identifier that it had, and the launcher keeps `dev.jerd.cli` instead of the file name
/// `JerdCLI` that a plain `--force` signature would give (fixes spec G 8.1 #2).
struct AppSigner: Sendable {
    /// The Sparkle parts below `Contents/Frameworks/Sparkle.framework`, in signing order.
    static let sparkleParts = [
        "Versions/B/XPCServices/Installer.xpc", "Versions/B/XPCServices/Downloader.xpc", "Versions/B/Autoupdate",
        "Versions/B/Updater.app", ".",
    ]
    static let sparkleFramework = "Contents/Frameworks/Sparkle.framework"

    /// The app's own code and its identifiers, signed after Sparkle; the app bundle is last.
    static let ownCode: [(path: String, identifier: String)] = [
        ("Contents/MacOS/JerdCLI", ReleaseNames.cliIdentifier),
        ("Contents/Library/LaunchServices/JerdHelper", ReleaseNames.helperIdentifier),
        ("", ReleaseNames.appIdentifier),
    ]

    let shell: ReleaseShell
    let signing: SigningIdentity

    func run(app: URL) async throws {
        let framework = app.appending(path: Self.sparkleFramework)
        for part in Self.sparkleParts {
            let path = part == "." ? framework : framework.appending(path: part)
            let identifier = try await currentIdentifier(of: path)
            let preserve = part.hasSuffix("Downloader.xpc") ? ["--preserve-metadata=entitlements"] : []
            try await sign(path, identifier: identifier, extra: preserve)
        }
        for code in Self.ownCode {
            try await sign(code.path.isEmpty ? app : app.appending(path: code.path), identifier: code.identifier)
        }
    }

    func sign(_ path: URL, identifier: String, extra: [String] = []) async throws {
        let arguments =
            ["--force", "--sign", signing.identity, "--options", "runtime", "--timestamp", "--identifier", identifier]
            + extra + [path.path]
        try await shell.run(SystemProgram.codesign, arguments, limit: TimeLimit.codeSigning)
    }

    /// The identifier of the current signature, read before the signature is replaced.
    func currentIdentifier(of path: URL) async throws -> String {
        let result = try await shell.run(
            SystemProgram.codesign, ["-d", "--verbose=2", path.path], limit: TimeLimit.codeSigning)
        guard let identifier = CodeSignatureDetails.parse(result.standardError).identifier, !identifier.isEmpty else {
            throw DevFailure.checkFailed("Cannot read the signing identifier of \(path.lastPathComponent).")
        }
        return identifier
    }
}
