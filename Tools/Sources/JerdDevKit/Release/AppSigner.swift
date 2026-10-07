import Foundation

/// Signs Sparkle's nested code, the launcher, the helper, and the app with Developer ID.
///
/// Archive signing leaves Sparkle's tools with their upstream signatures, so they are signed again in
/// Sparkle's documented order, innermost first. Every signature names its identifier: Sparkle keeps
/// the identifier that it had, and the launcher keeps `dev.jerd.cli` instead of the file name
/// `JerdCLI` that a plain `--force` signature would give.
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
    /// The certificate (SHA-1 or name) that signs everything.
    let identity: String

    func run(app: URL) async throws {
        try await signSparkle(in: app)
        for code in Self.ownCode {
            try await sign(code.path.isEmpty ? app : app.appending(path: code.path), identifier: code.identifier)
        }
    }

    /// Signs Sparkle's nested code of `app`, innermost first. `./dev check updates` signs its test apps
    /// with this function too, so a real Sparkle update proves these signatures.
    func signSparkle(in app: URL) async throws {
        let framework = app.appending(path: Self.sparkleFramework)
        for part in Self.sparkleParts {
            let path = part == "." ? framework : framework.appending(path: part)
            let identifier = Self.identifier(of: part, current: try await currentIdentifier(of: path))
            let preserve = part.hasSuffix("Downloader.xpc") ? ["--preserve-metadata=entitlements"] : []
            try await sign(path, identifier: identifier, extra: preserve)
        }
    }

    func sign(_ path: URL, identifier: String, extra: [String] = []) async throws {
        let arguments =
            ["--force", "--sign", identity, "--options", "runtime", "--timestamp", "--identifier", identifier]
            + extra + [path.path]
        try await shell.run(SystemProgram.codesign, arguments, limit: TimeLimit.codeSigning)
    }

    /// Sparkle's own identifier of the `Autoupdate` tool. The Sparkle package ships the tool with an
    /// ad-hoc signature whose identifier is `Autoupdate-<hash>`, which is not stable across builds.
    static let autoupdateIdentifier = "org.sparkle-project.Sparkle.Autoupdate"

    /// The identifier of a Sparkle part: its current one, except for `Autoupdate`, which has no bundle
    /// and gets Sparkle's product identifier.
    static func identifier(of part: String, current: String) -> String {
        part.hasSuffix("/Autoupdate") && !current.hasPrefix("org.sparkle-project.") ? autoupdateIdentifier : current
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
