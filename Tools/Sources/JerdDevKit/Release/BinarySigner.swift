import Foundation
import JerdFoundation

/// Signs one runtime Mach-O file with Developer ID: arm64 only, reviewed entitlements, the hardened
/// runtime, a secure timestamp, and an explicit identifier.
struct BinarySigner: Sendable {
    let shell: ReleaseShell
    let signing: SigningIdentity
    /// The folder for the entitlement files of the signatures.
    let entitlementsFolder: URL

    func sign(_ file: URL, identifier: String, isPHP: Bool) async throws {
        try await keepOnlyARM64(file)
        let entitlements = try EntitlementPolicy.entitlements(
            existing: try await existingEntitlements(file), isPHP: isPHP, file: file.lastPathComponent)
        var arguments = [
            "--force", "--timestamp", "--options", "runtime", "--sign", signing.identity, "--identifier", identifier,
        ]
        if !entitlements.isEmpty {
            try FileManager.default.createDirectory(at: entitlementsFolder, withIntermediateDirectories: true)
            let plist = entitlementsFolder.appending(path: FileDigest.hexSHA256(of: Data(file.path.utf8)) + ".plist")
            try EntitlementPolicy.plist(entitlements).write(to: plist)
            arguments += ["--entitlements", plist.path, "--generate-entitlement-der"]
        }
        try await shell.run(SystemProgram.codesign, arguments + [file.path], limit: TimeLimit.codeSigning)
        try await shell.run(SystemProgram.codesign, ["--verify", "--strict", file.path], limit: TimeLimit.codeSigning)
    }

    /// A universal file keeps only its arm64 slice. A file without arm64 cannot run on Apple silicon.
    func keepOnlyARM64(_ file: URL) async throws {
        let output = try await shell.output(SystemProgram.lipo, ["-archs", file.path], limit: TimeLimit.probe)
        let architectures = MachOFile.architectures(output)
        guard architectures.contains(ReleaseNames.architecture) else {
            throw DevFailure.checkFailed("\(file.lastPathComponent) has no arm64 code.")
        }
        guard architectures != [ReleaseNames.architecture] else { return }
        let thin = file.appendingPathExtension("arm64")
        try await shell.run(
            SystemProgram.lipo, [file.path, "-thin", "arm64", "-output", thin.path], limit: TimeLimit.probe)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]
        try FileManager.default.setAttributes([.posixPermissions: mode ?? 0o700], ofItemAtPath: thin.path)
        guard rename(thin.path, file.path) == 0 else {
            throw DevFailure.checkFailed("Cannot replace \(file.path) with its arm64 slice.")
        }
    }

    /// The entitlements XML of the current signature, or empty data for an unsigned file.
    func existingEntitlements(_ file: URL) async throws -> Data {
        let result = try await shell.result(
            SystemProgram.codesign, ["-d", "--entitlements", "-", "--xml", file.path], limit: TimeLimit.codeSigning)
        if result.succeeded { return Data(result.standardOutput.utf8) }
        if result.standardError.contains("not signed at all") { return Data() }
        throw DevFailure.checkFailed("Cannot read the signature of \(file.lastPathComponent): \(result.standardError)")
    }
}
