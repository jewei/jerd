import Foundation

/// Verifies a signed release app: Info.plist, the whole bundle, every nested signature with its
/// identifier, arm64-only executables, and the signed runtime payloads.
struct AppVerifier: Sendable {
    /// One signed file and the identifier that it must have.
    struct SignedCode: Equatable, Sendable {
        var file: URL
        var identifier: SignatureVerifier.IdentifierRule
    }

    /// The executables that must contain only arm64 (fixes spec G 8.1 #16: not only the main one).
    static let arm64Executables = [
        "Contents/MacOS/Jerd", "Contents/MacOS/JerdCLI", "Contents/Library/LaunchServices/JerdHelper",
    ]

    let shell: ReleaseShell
    let team: String
    let info: AppInfoCheck

    func verify(_ app: URL, notarized: Bool) async throws {
        try info.check(AppInfoCheck.read(app))
        try await shell.run(
            SystemProgram.codesign, ["--verify", "--deep", "--strict", app.path], limit: TimeLimit.codeSigning)
        let payloads = AppPayloadCheck(shell: shell, team: team, minimumMacOS: info.minimumMacOS)
        let payloadCode = try await payloads.verify(app.appending(path: "Contents/Resources/RuntimePayloads"))
        let verifier = SignatureVerifier(shell: shell, team: team)
        for code in try Self.bundleCode(app) + payloadCode {
            try await verifier.verify(code.file, identifier: code.identifier)
        }
        for path in Self.arm64Executables {
            let output = try await shell.output(
                SystemProgram.lipo, ["-archs", app.appending(path: path).path], limit: TimeLimit.probe)
            guard MachOFile.architectures(output) == [ReleaseNames.architecture] else {
                throw DevFailure.checkFailed("\(path) must contain only arm64 code.")
            }
        }
        if notarized {
            try await shell.xcrun(["stapler", "validate", app.path], limit: TimeLimit.assessment)
            try await shell.run(
                SystemProgram.spctl, ["--assess", "--type", "execute", "--verbose=2", app.path],
                limit: TimeLimit.assessment)
        }
        shell.console.success("The app, its nested code, and its runtime payloads are signed correctly.")
    }

    /// The app, its own executables, Sparkle's parts with their bundle identifiers, and every other
    /// Mach-O file below `Contents/Frameworks`.
    static func bundleCode(_ app: URL) throws -> [SignedCode] {
        var code = [SignedCode(file: app, identifier: .exact(ReleaseNames.appIdentifier))]
        for own in AppSigner.ownCode where !own.path.isEmpty {
            code.append(SignedCode(file: app.appending(path: own.path), identifier: .exact(own.identifier)))
        }
        let framework = app.appending(path: AppSigner.sparkleFramework)
        for part in AppSigner.sparkleParts {
            let file = part == "." ? framework : framework.appending(path: part)
            let plist = part == "." ? "Versions/B/Resources/Info.plist" : "Contents/Info.plist"
            if part.hasSuffix("Autoupdate") {
                code.append(SignedCode(file: file, identifier: .prefix("org.sparkle-project.")))
            } else {
                let base = part == "." ? framework : file
                code.append(
                    SignedCode(file: file, identifier: .exact(try bundleIdentifier(base.appending(path: plist)))))
            }
        }
        let listed = Set(code.map(\.file.standardizedFileURL.path))
        for file in try machOFiles(below: app.appending(path: "Contents/Frameworks"))
        where !listed.contains(file.standardizedFileURL.path) {
            code.append(SignedCode(file: file, identifier: .any))
        }
        return code
    }

    static func bundleIdentifier(_ plist: URL) throws -> String {
        guard let data = try? Data(contentsOf: plist),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let identifier = info["CFBundleIdentifier"] as? String
        else { throw DevFailure.checkFailed("Cannot read the bundle identifier in \(plist.path).") }
        return identifier
    }

    /// Regular Mach-O files below `folder`, sorted. Symbolic links (framework version links) are skipped.
    static func machOFiles(below folder: URL) throws -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true, values.isSymbolicLink != true, MachOFile.isMachO(url) {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }
}
